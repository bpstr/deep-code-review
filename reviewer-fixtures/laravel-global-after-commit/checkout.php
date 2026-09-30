<?php
use App\Jobs\SendInvoice;
use App\Models\Invoice;
use Illuminate\Support\Facades\DB;
function checkout(array $validated): void {
    DB::transaction(function () use ($validated) {
        $invoice = Invoice::create($validated);
        SendInvoice::dispatch($invoice->id);
    });
}
