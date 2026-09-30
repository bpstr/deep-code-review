<?php
function maintenance_node_count(): int {
    return (int) \Drupal::entityQuery('node')->accessCheck(FALSE)->count()->execute();
}
