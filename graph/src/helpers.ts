import { RefChange, Transaction } from "./types";

// Helper function to determine the type of Transaction
function getTransactionType(transaction: Transaction): "single" | "trade" | "transfer" {
    if ("single" in transaction) return "single";
    if ("trade" in transaction) return "trade";
    if ("transfer" in transaction) return "transfer";
    throw new Error("Unknown transaction type");
}

// Helper function to determine the type of RefChange
function getRefChangeType(refChange: RefChange): "create" | "remove" | "move" | "split" | "convert" {
    if ("create" in refChange) return "create";
    if ("remove" in refChange) return "remove";
    if ("move" in refChange) return "move";
    if ("split" in refChange) return "split";
    if ("convert" in refChange) return "convert";
    throw new Error("Unknown RefChange type");
}
