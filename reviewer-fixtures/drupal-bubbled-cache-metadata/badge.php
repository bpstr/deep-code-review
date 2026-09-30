<?php
use Drupal\Core\Cache\CacheableMetadata;
function account_badge(): array {
    $build = [
        '#plain_text' => 'Account ' . \Drupal::currentUser()->id(),
        '#cache' => ['keys' => ['account_badge'], 'max-age' => 3600],
    ];
    (new CacheableMetadata())->setCacheContexts(['user'])->applyTo($build);
    return $build;
}
