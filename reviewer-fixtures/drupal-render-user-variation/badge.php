<?php
function account_badge(): array {
    return [
        '#plain_text' => 'Account ' . \Drupal::currentUser()->id(),
        '#cache' => ['keys' => ['account_badge'], 'max-age' => 3600],
    ];
}
