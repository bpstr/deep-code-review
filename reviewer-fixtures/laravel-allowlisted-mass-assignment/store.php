<?php
use App\Models\Task;
use Illuminate\Support\Facades\Gate;
function store_task(): Task {
    Gate::authorize('create', Task::class);
    $attributes = request()->validate(['title' => 'required|string|max:80']);
    return Task::create($attributes);
}
