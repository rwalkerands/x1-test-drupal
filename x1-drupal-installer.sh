#!/usr/bin/env bash

# Create a new instance of Drupal configured as the X1 project.

# x1-drupal-installer.sh options...

# Valid options:
# -e environment_filename
#     Required: Filename of file containing the environment description.
#     Must be a shell script that defines environment variables
#     as used in this script.

# Check requirements: PHP 7.4.

# Local settings file. Relative to the sites directory.
# NB: The value set here must match the value used in settings.php below.
LOCAL_SETTINGS=settings/settings.local.php
requireLocalSettings() {
    if [[ ! -s "${LOCAL_SETTINGS}" ]] ; then
    echo '<?php' > "${LOCAL_SETTINGS}"
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
# Support optional SI_SITES_SUBDIR setting.
SI_SITES_SUBDIR_OPTION=""
if [[ -n "${SI_SITES_SUBDIR}" ]] ; then
    SITE_SUBDIR="${SI_SITES_SUBDIR}"
    DRUSH_URI="--uri=${SI_SITES_SUBDIR}"
    SI_SITES_SUBDIR_OPTION="--sites-subdir=${SI_SITES_SUBDIR}"
else
    SITE_SUBDIR=default
    DRUSH_URI=""
fi

# Require that neither or both FILE_PUBLIC_PATH and FILE_PUBLIC_BASE_URL
# be specified.
# xor: https://stackoverflow.com/questions/56700325/xor-conditional-in-bash
if [[ "${FILE_PUBLIC_PATH:+A}" != "${FILE_PUBLIC_BASE_URL:+A}" ]]; then
    echo Specified only one of FILE_PUBLIC_PATH and FILE_PUBLIC_BASE_URL.
    exit 1
fi
# Ditto with MAIN_SITE_REDIRECT_PATH.
if [[ "${FILE_PUBLIC_PATH:+A}" != "${MAIN_SITE_REDIRECT_PATH:+A}" ]]; then
    echo Specified only one of FILE_PUBLIC_PATH and MAIN_SITE_REDIRECT_PATH.
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

# Define scripts to remove the embedded .git directories
# that we get because of requiring development versions.
# Specify -prune to avoid these errors:
#  "find: web/modules/contrib/mimemail/.git: No such file or directory";
#  see https://stackoverflow.com/a/38980693/3765696 .
composer config scripts.removeEmbeddedGit \
  "find web/modules -name .git -prune -exec rm -rf '{}' ';'"
# Doesn't work yet:
#composer config scripts-descriptions.removeEmbeddedGit \
#  "Remove .git directories found in modules"
composer config scripts.post-install-cmd \
  "@removeEmbeddedGit"
composer config scripts.post-update-cmd \
  "@removeEmbeddedGit"

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
# We need dev versions of some modules. Because they have lower stability,
# they must be installed at the "top level":
#  mimemail.
#  typed_data. Needed for format_text("...") filter.
#  rules.
#  tr_rulez.
# Was:
# composer require drupal/backup_migrate:^5.0.x-dev \
#  drupal/mimemail:1.x-dev#e72b92ec \
#  drupal/typed_data:1.x-dev#27555f47 \
#  drupal/rules:3.x-dev#615221d \
#  drupal/tr_rulez:1.x-dev
# But now some dev code has been incorporated into a release. So now:
composer require \
 drupal/mimemail:1.x-dev#e72b92ec \
 drupal/typed_data:1.x-dev#27555f47 \
 drupal/rules:3.x-dev#615221d \
 drupal/tr_rulez:1.x-dev

# Now we're ready to install our project module.
composer require ardc/x1-custom-module-x1

# We will do some patching; use composer-patches for this.
# We apply the patches only _after_ installing all our custom modules;
# patches against drupal/core aren't done otherwise.
composer require cweagans/composer-patches:~1.0 --update-with-dependencies

# Now we know where drush is.
DRUSH="${ROOT}/${INST_DIR}/vendor/bin/drush ${DRUSH_URI}"

# Patch vendor/drush/drush/src/Sql/SqlMysql.php
# to use the correct character set and collation for MySQL.
# No, we no longer need to do this here; we do it using a patch specified
# in x1-custom-module-x1's composer.json.
# sed -i -e \
# 's+DEFAULT CHARACTER SET utf8 +DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci +' \
#   vendor/drush/drush/src/Sql/SqlMysql.php

# Site install. Creates and initializes the database.
${DRUSH} -y si \
  --db-url="${SI_DB_URL}" \
  --db-su="${SI_DB_SU}" \
  --db-su-pw="${SI_DB_SU_PW}" \
  --account-name="${SI_ACCOUNT_NAME}" \
  --account-mail="${SI_ACCOUNT_MAIL}" \
  --site-mail="${SI_SITE_MAIL}" \
  --account-pass="${SI_ACCOUNT_PASS}" \
  --locale="${SI_LOCALE}" \
  --site-name="${SI_SITE_NAME}" \
  ${SI_SITES_SUBDIR_OPTION}

cd web/sites
# $sites['localhost.example'] = 'example.com';
# Support optional SI_SITES_SUBDIR setting. If it was given,
# we now have a sites.php file.
# If SITES_KEY is also given, add it to sites.php.
if [[ -n "${SI_SITES_SUBDIR}" && -n "${SITES_KEY}" ]] ; then
    echo "\$sites['${SITES_KEY}'] = '${SI_SITES_SUBDIR}';" >> sites.php
fi

cd ${SITE_SUBDIR}
chmod +w . settings.php settings settings/*
# Add trusted_host_patterns setting.
# Use a trick to make idempotent; we don't want to lose
# the original settings.php!
mkdir settings && mv settings.php settings/settings.original.php

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

# Set file_private_path; we provide a default, relative to web.
: "${FILE_PRIVATE_PATH:=../private}"
cat > settings/file_private_path.php <<EOF
<?php

\$settings['file_private_path'] = '${FILE_PRIVATE_PATH}';
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
    requireLocalSettings

    if [[ "${ENVIRONMENT_INDICATOR}" =~ ^[a-z]+$ ]]  ; then
        # One of our predefined values specified.
        echo "\$config['environment_indicator.indicator'] = \$environment_indicator_indicators['${ENVIRONMENT_INDICATOR}'];" >> \
             "${LOCAL_SETTINGS}"
    else
        # Array value specified; copy it in literally.
        # Yes, this _is_ one of many injection vulnerabilities, so make sure
        # you control your INI files!
        echo "\$config['environment_indicator.indicator'] = ${ENVIRONMENT_INDICATOR};" >> \
             "${LOCAL_SETTINGS}"
    fi
fi

# Now support FILE_PUBLIC_PATH and FILE_PUBLIC_BASE_URL.
if [[ -n "${FILE_PUBLIC_PATH}" ]] ; then
    # We need settings.local.php.
    requireLocalSettings

    if [[ -e "${FILE_PUBLIC_PATH}" ]] ; then
        # Destination already exists; try renaming it.
        mv -f "${FILE_PUBLIC_PATH}" "${FILE_PUBLIC_PATH}-$(date '+%s')" || \
            { echo "Unable to rename existing public path" ; exit 1 ; }
    fi
    # Now move it into place.
    mv -f files "${FILE_PUBLIC_PATH}" || \
            { echo "Unable to move public files directory" ; exit 1 ; }
    cat >> "${LOCAL_SETTINGS}" <<EOF

\$settings['file_public_base_url'] = '${FILE_PUBLIC_BASE_URL}';
\$settings['file_public_path'] = '${FILE_PUBLIC_PATH}';
# In case we ever want to use it, set config_sync_directory.
# NB: we don't create this directory here.
\$settings['config_sync_directory'] = '${FILE_PRIVATE_PATH}/config_sync';
EOF
    # TODO: Now update .htaccess
    # Update .htaccess in the files directory, so that
    # Requests for non-existent files are redirected to Drupal.
    chmod u+w "${FILE_PUBLIC_PATH}/.htaccess"
    cat >> "${FILE_PUBLIC_PATH}/.htaccess" <<EOF


RewriteEngine on
# Make sure Authorization HTTP header is available to PHP
# even when running as CGI or FastCGI.
RewriteRule ^ - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteCond %{REQUEST_URI} !=/favicon.ico
RewriteRule ^ ${MAIN_SITE_REDIRECT_PATH}index.php [L]
EOF
    chmod u-w "${FILE_PUBLIC_PATH}/.htaccess"
fi

cat > settings.php <<'EOF'
<?php

include __DIR__ . '/settings/settings.original.php';
include __DIR__ . '/settings/trusted_host_patterns.php';
include __DIR__ . '/settings/file_private_path.php';
include __DIR__ . '/settings/environment_indicator_indicators.php';

if (file_exists(__DIR__ . '/settings/settings.local.php')) {
  include __DIR__ . '/settings/settings.local.php';
}
EOF

chmod -w . settings.php settings settings/*

# Back up to the web directory ...
cd ../..

# Create private directory for use by backup_migrate backups.
# Hmm, still needed?
# TODO: ensure writable by PHP
#mkdir -p "${FILE_PRIVATE_PATH}/backup_migrate"
mkdir -p "${FILE_PRIVATE_PATH}/backups"

# ... and now back to the top level of the installation.
cd ..

# Clear cache; necessary to force reloading of settings.
${DRUSH} cr

# Enable the custom theme.
${DRUSH} theme:enable agldwg
# Make it the default.
${DRUSH} cset -y system.theme default agldwg

# Enable modules.
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

# Move the user account menu to the sidebar.
${DRUSH} cset -y block.block.agldwg_account_menu region sidebar_first
${DRUSH} cset -y block.block.agldwg_account_menu settings.label_display visible

# Hide the breadcrumbs, because they're often wrong/misleading, and
# we aren't going to fix them (yet).
${DRUSH} cset -y --input-format=yaml --value=false \
         block.block.agldwg_breadcrumbs status

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

# (Temporary, we hope) workaround for readonlymode so that the list
# views (/vocabularies, etc.) continue to work when in read-only mode. See:
#   https://www.drupal.org/project/readonlymode/issues/3228261
ROM_FORMS=$( ${DRUSH} cget --format=yaml \
                      readonlymode.settings forms.default.edit)
if [[ "${ROM_FORMS}" != "*views_exposed_form*" ]] ; then
    ${DRUSH} cset -y readonlymode.settings forms.additional.edit \
             views_exposed_form
fi

# Dodgy, but convenient: run environment-specific code.
if [[ "$(type -t extra_installation)" == "function" ]]; then
    extra_installation
fi

# And finally, clear the cache to ensure that everything's in sync.
${DRUSH} cr
