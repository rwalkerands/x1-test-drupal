<?php

include (drupal_get_path('theme', 'bartik') . '/color/color.inc'); 

$info['schemes']['default'] = [
      'title' => t('AGLDWG (default)'),
      'colors' => [
        'top' => '#4a4a4a',
        'bottom' => '#4e4e4e',
        'bg' => '#ffffff',
        'sidebar' => '#f6f6f2',
        'sidebarborders' => '#d0d0d0',
        'footer' => '#161617',
        'titleslogan' => '#ffffff',
        'text' => '#3b3b3b',
        'link' => '#994F00',
      ],
    ];

$info['copy'] = [
//    'images/agldwg-logo-ochre-dark.png',
  ];


  // Attachments.
  // Put the logo path into JavaScript for the live preview.
$info['#attached']['drupalSettings']['color']['logo'] =
    theme_get_setting('logo.url', 'agldwg');

