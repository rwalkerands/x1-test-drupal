#!/usr/bin/env bash

# Create a new instance of Drupal configured as the X1 project.

# x1-drupal-installer.sh options...

# Valid options:
# -e environment_filename
#     Required: Filename of file containing the environment description.
#     Must be a shell script that defines environment variables
#     as used in this script.

# Check requirements: PHP 7.4.

createLocalSettings() {
    if [[ ! -s settings/settings.local.php ]] ; then
    echo '<?php' > settings/settings.local.php
    fi
}

PHP_VERSION=$(php -r 'echo PHP_VERSION_ID;' 2>/dev/null)
if [[ -z ${PHP_VERSION} ]] ; then
    echo No PHP, or unknown PHP version.
    exit 1
fi
if [[ ${PHP_VERSION} < 70400 ]] ; then
    echo PHP version less than 7.4.
    exit 1
fi

# Where are we?
ROOT="${PWD}"

# Command-line processing as per ABS Example 15-21
# ("Using getopts to read the options/arguments passed to a script"):
# https://www.tldp.org/LDP/abs/html/internal.html#EX33

if [ $# -eq 0 ]    # Script invoked with no command-line args?
then
  echo "Usage: $(basename "$0") options... (-e:)"
  exit 1
fi


while getopts "e:" Option; do
    case $Option in
        e ) X1_ENV="$OPTARG"
            if [[ -z "${X1_ENV}" || ! -r "${X1_ENV}" ]]
            then
                echo Invalid argument to -e: "${X1_ENV}"
                exit 1
            fi ;;
        * ) echo "Unimplemented option chosen." ; exit 1;;   # Default.
    esac
done

# Ensure valid arguments were specified
if [[ -z "${X1_ENV}" ]]
then
    echo No -e option specified
    exit 1
fi

# May as well source the environment now.
source "${X1_ENV}"

# Require that INST_DIR have a value.
if [[ -z "${INST_DIR}" ]]
then
    echo No INST_DIR setting specified
    exit 1
fi

# Require that SI_* have values.
if [[ -z "${SI_DB_URL}" || -z "${SI_DB_SU}" || -z "${SI_DB_SU_PW}" ||
      -z "${SI_SITE_MAIL}" || -z "${SI_ACCOUNT_NAME}" ||
      -z "${SI_ACCOUNT_MAIL}" || -z "${SI_ACCOUNT_PASS}" ||
      -z "${SI_LOCALE}" || -z "${SI_SITE_NAME}" ]]
then
    echo There is a missing SI_ setting.
    exit 1
fi

# Creates the installation as a new subdirectory
# of the current directory; it must not already exist.

if [[ -e ${INST_DIR} ]] ; then
    echo Installation directory ${INST_DIR} already exists.
    exit 1
fi


# INST_VERSION is optional; if omitted, you'll get the latest version
composer create-project drupal/recommended-project ${INST_DIR} ${INST_VERSION}
cd $INST_DIR

# Enable patching by dependencies, i.e., by our custom module x1.
# Use --json so that we get the proper Boolean value true and not
# the string value "true".
composer config --json extra.enable-patching true

composer config repositories.x1-custom-theme-agldwg \
  vcs https://github.com/rwalkerands/x1-custom-theme-agldwg.git
composer config repositories.x1-custom-module-x1 \
  vcs https://github.com/rwalkerands/x1-custom-module-x1.git
composer config repositories.x1-custom-module-x1-block-content \
  vcs https://github.com/rwalkerands/x1-custom-module-x1-block-content.git
# # Because backup_migrate:^5.0.0-rc2 has lower stability,
# # it must be installed at the "top level".
# #composer require drupal/backup_migrate:^5.0.0-rc2
# No, backup_migrate 5.0.0-rc2 has annoying defects, i.e.,
# can't backup "Entire Site". Use dev instead.
# Sigh, similar story for mimemail.
# Sigh, similar story for typed_data. Needed for format_text("...") filter.
# Sigh, similar story for rules.
# Sigh, similar story for tr_rulez.
composer require drupal/backup_migrate:^5.0.x-dev \
 drupal/mimemail:1.x-dev#e72b92ec \
 drupal/typed_data:1.x-dev#27555f47 \
 drupal/rules:3.x-dev#615221d \
 drupal/tr_rulez:1.x-dev

composer require ardc/x1-custom-module-x1

# We will do some patching; use composer-patches for this.
# Apply the patches after installing all our custom modules,
# patches against drupal/core aren't done otherwise.
composer require cweagans/composer-patches:~1.0 --update-with-dependencies

# Now we know where drush is.
DRUSH=${ROOT}/${INST_DIR}/vendor/bin/drush

# Patch vendor/drush/drush/src/Sql/SqlMysql.php
# to use the correct character set and collation for MySQL:
sed -i -e \
's+DEFAULT CHARACTER SET utf8 +DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci +' \
  vendor/drush/drush/src/Sql/SqlMysql.php

# Site install. Creates and initializes the database.
${DRUSH} -y si \
  --db-url="${SI_DB_URL}" \
  --db-su="${SI_DB_SU}" \
  --db-su-pw="${SI_DB_SU_PW}" \
  --site-mail="${SI_SITE_MAIL}" \
  --account-name="${SI_ACCOUNT_NAME}" \
  --account-mail="${SI_ACCOUNT_MAIL}" \
  --account-pass="${SI_ACCOUNT_PASS}" \
  --locale="${SI_LOCALE}" \
  --site-name="${SI_SITE_NAME}"

cd web/sites/default
chmod +w . settings.php settings settings/*
# Add trusted_host_patterns setting to shared settings.
# use a trick to make idempotent; we don't want to lose
# the original settings.php!
mkdir settings && mv settings.php settings/settings.shared.php

# Create settings/trusted_host_patterns.php from three
# sections: header; list of trusted host patterns; trailer.
# Header ...
cat > settings/trusted_host_patterns.php <<'EOF'
<?php

$settings['trusted_host_patterns'] = [
EOF

# ... list of trusted host patterns ...
if [[ -n "${TRUSTED_HOST_PATTERNS}" ]] ; then
    echo "${TRUSTED_HOST_PATTERNS}"  >> settings/trusted_host_patterns.php
else
    cat >> settings/trusted_host_patterns.php <<'EOF'
  '^localhost$',
EOF
fi

# ... trailer.
cat >> settings/trusted_host_patterns.php <<'EOF'
];
EOF


cat > settings/file_private_path.php <<'EOF'
<?php

$settings['file_private_path'] = '../private';
EOF

cat > settings/environment_indicator_indicators.php <<'EOF'
<?php
$environment_indicator_indicators = array(
  'production' => array(
    'bg_color' => '#ef5350',
    'fg_color' => '#ffffff',
    'name' => 'production'
  ),
  'staging' => array(
    'bg_color' => '#fff176',
    'fg_color' => '#000000',
    'name' => 'staging'
  ),
  'test' => array(
    'bg_color' => '#4caf50',
    'fg_color' => '#000000',
    'name' => 'test'
  ),
  'development' => array(
    'bg_color' => '#4caf50',
    'fg_color' => '#000000',
    'name' => 'development'
  ),
  'local' => array(
    'bg_color' => '#006600',
    'fg_color' => '#ffffff',
    'name' => 'local machine'
  ),
);
EOF
if [[ -n "${ENVIRONMENT_INDICATOR}" ]] ; then
    # We need settings.local.php; create it.
    createLocalSettings

    if [[ "${ENVIRONMENT_INDICATOR}" =~ ^[a-z]+$ ]]  ; then
        # One of our predefined values specified.
        echo "\$config['environment_indicator.indicator'] = \$environment_indicator_indicators['${ENVIRONMENT_INDICATOR}'];" >> \
             settings/settings.local.php
    else
        # Array value specified; copy it in literally.
        # Yes, this _is_ an injection vulnerability, so make sure you
        # control your INI files!
        echo "\$config['environment_indicator.indicator'] = ${ENVIRONMENT_INDICATOR};" >> \
             settings/settings.local.php
    fi
fi

cat > settings.php <<'EOF'
<?php

include __DIR__ . '/settings/settings.shared.php';
include __DIR__ . '/settings/trusted_host_patterns.php';
include __DIR__ . '/settings/file_private_path.php';
include __DIR__ . '/settings/environment_indicator_indicators.php';

if (file_exists(__DIR__ . '/settings/settings.local.php')) {
  include __DIR__ . '/settings/settings.local.php';
}
EOF

chmod -w . settings.php settings settings/*
cd ../../..

# create private directory for use by backup_migrate manual backups
# TODO: ensure writable by PHP
mkdir -p private/backup_migrate
mkdir -p private/backups

# Clear cache necessary to force reloading of settings.
${DRUSH} cr

# enable custom theme
${DRUSH} theme:enable agldwg
# make it the default
${DRUSH} cset -y system.theme default agldwg

# Support updating the href attributes of the links in the "Add
# Content Types" block content, in case the site is not hosted at the
# top level.  (The custom block uses href="/node/add/...".)  Achieve
# this by patching the migration content in advance of running the
# migration.
if [[ -n "${SITE_PREFIX}" ]]
then
    sed -i -e 's+"/node/add+"'${SITE_PREFIX}'/node/add+g' web/modules/custom/x1-custom-module-x1-block-content/data/block_content/basic/block_content-1.json
fi

# Enable modules
${DRUSH} en -y x1 x1_eme_block_content

# AFTER enabling the x1 module, run this to import the
# registry_item_status taxonomy:
${DRUSH} cim --partial -y \
         --source=modules/custom/x1-custom-module-x1/config/taxonomies
${DRUSH} it --choice=force

# AFTER enabling the x1_eme_block_content module, run this to import and
# use the custom block content:
${DRUSH} migrate:import --all --execute-dependencies
${DRUSH} cim --partial --source=modules/custom/x1-custom-module-x1/config/blocks -y

# Configure the backup destination directory.
# NB 1: the directory must be writable.
# NB 2: the path must use a "stream", i.e., have "://" in it.
${DRUSH} cset -y backup_migrate.backup_migrate_destination.x1_backups \
         config.directory private://backups
# NB: After a subsequent syncing of the config, you may (?) have to
# reset this config value.

# Move the user account menu to the sidebar:
${DRUSH} cset -y block.block.agldwg_account_menu region sidebar_first
${DRUSH} cset -y block.block.agldwg_account_menu settings.label_display visible

# Region and language settings.
# Set default country to Australia.
${DRUSH} cset -y system.date country.default 'AU'
# Allow users to set their own timezone at registration time.
${DRUSH} cset -y system.date timezone.user.default 2
# Show revision dates as DD/MM/YYYY, not as MM/DD/YYYY.
${DRUSH} cset -y core.date_format.short pattern 'd/m/Y - H:i'
${DRUSH} cset -y core.date_format.medium pattern 'D, d/m/Y - H:i'
# Also long date format
# (it was 'l, F j, Y - H:i')
${DRUSH} cset -y core.date_format.long pattern 'l, j F Y - H:i'
# Need to clear cache after changing those settings.
# OK, but do it later, because there's more stuff to be done.
# ${DRUSH} cr

# Roles and permissions.

# Ensure administrator role will continue to come last, i.e., after
# we add our custom 'control body' and 'registry manager' roles.
${DRUSH} cset -y user.role.administrator weight 10

# Allow anonymous and authenticated users to view the fields that
# have custom permissions.
${DRUSH} role:perm:add anonymous \
  'view field_date_accepted,view field_registry_status,view field_reviewer'
${DRUSH} role:perm:add authenticated \
  'view field_date_accepted,view field_registry_status,view field_reviewer'

# Permissions for comments.
# Don't allow anonymous users to view comments.
${DRUSH} role:perm:remove anonymous \
  'access comments'
# Allow authenticated users to edit their own comments.
${DRUSH} role:perm:add authenticated \
  'edit own comments'

# Allow authenticated users to create and update their own
# dataset, ontology, and vocabulary content:
${DRUSH} role:perm:add authenticated \
  'create dataset content,create ontology content,create vocabulary content,edit own dataset content,edit own ontology content,edit own vocabulary content'
# (Organisation and registry content is restricted to the control body
# and registry manager roles.)

# Allow authenticated users to _view_ revisions:
${DRUSH} role:perm:add authenticated \
  'view dataset revisions,view ontology revisions,view organisation revisions,view register revisions,view vocabulary revisions'

# Create control body role. We do it this way (i.e., using drush,
# not a config file), so that we get the extra
# system.action.user_add_role_action.control_body and
# system.action.user_remove_role_action.control_body config created for us.
${DRUSH} role:create 'control_body' 'Control body user'
# Set weight to 2, i.e., between authenticated and registry manager.
${DRUSH} cset -y user.role.control_body weight 2
# Allow control body users to create and update organisation and register
# content, and to delete and edit all content and administer comments.
# NB: The list of permissions should match that for registry manager below.
${DRUSH} role:perm:add control_body \
  'administer comments,create organisation content,create register content,delete any dataset content,delete any ontology content,delete any organisation content,delete any register content,delete any vocabulary content,edit any dataset content,edit any ontology content,edit any organisation content,edit any register content,edit any vocabulary content,edit field_date_accepted,edit field_registry_status,edit field_reviewer'

# Create registry manager role. We do it this way (i.e., using drush,
# not a config file), so that we get the extra
# system.action.user_add_role_action.registry_manager and
# system.action.user_remove_role_action.registry_manager config created for us.
${DRUSH} role:create 'registry_manager' 'Registry manager user'
# Set weight to 3, i.e., between control body and administrator.
${DRUSH} cset -y user.role.registry_manager weight 3
# Allow registry manager users to create and update organisation and register
# content, and to delete and edit all content and administer comments.
# NB: The list of permissions should match that for control body above.
${DRUSH} role:perm:add registry_manager \
  'administer comments,create organisation content,create register content,delete any dataset content,delete any ontology content,delete any organisation content,delete any register content,delete any vocabulary content,edit any dataset content,edit any ontology content,edit any organisation content,edit any register content,edit any vocabulary content,edit field_date_accepted,edit field_registry_status,edit field_reviewer'

# Mailsystem settings
${DRUSH} cset --input-format=yaml -y \
         mailsystem.settings modules.rules.none - <<EOF
formatter: mime_mail
sender: mime_mail
EOF

# Mimemail settings
# Email sender settings fall back to SI_SITE_NAME and SI_ACCOUNT_MAIL
: "${RULES_EMAIL_SENDER:=${SI_ACCOUNT_MAIL}}"
: "${RULES_EMAIL_NAME:=${SI_SITE_NAME}}"

${DRUSH} cset -y mimemail.settings mail "${RULES_EMAIL_SENDER}"
${DRUSH} cset -y mimemail.settings name "${RULES_EMAIL_NAME}"
${DRUSH} cset -y mimemail.settings format "full_html_email"

# CONTACT_FEEDBACK_MAIL is optional. Drupal defaults to sending
# the feedback contact form submissions to the site_email setting.
if [[ -n "${CONTACT_FEEDBACK_MAIL}" ]] ; then
    ${DRUSH} cset -y --input-format=yaml \
             --value="[ ${CONTACT_FEEDBACK_MAIL} ]" \
             contact.form.feedback recipients
fi

# Dodgy, but convenient: run environment-specific code.
if [[ "$(type -t extra_installation)" == "function" ]]; then
    extra_installation
fi

# And finally, clear the cache to ensure that everything's in sync.
${DRUSH} cr
