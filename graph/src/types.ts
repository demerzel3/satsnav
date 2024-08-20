// Enum for Asset types
export enum AssetType {
    Fiat = 0,
    Crypto = 1,
}

// Enum for LedgerEntry types
export enum LedgerEntryType {
    Deposit = 0,
    Withdrawal = 1,
    Trade = 2,
    Interest = 3,
    Bonus = 4,
    Fee = 5,
    Transfer = 6,
}

// Asset type
export interface Asset {
    name: string;
    type: AssetType;
}

// LedgerEntry type
export interface LedgerEntry {
    wallet: string;
    id: string;
    groupId: string;
    date: number; // Unix timestamp
    type: LedgerEntryType;
    amount: number; // Decimal is represented as a number in JSON
    asset: Asset;
}

// Ref type
export interface Ref {
    id: string;
    asset: Asset;
    amount: number; // Decimal is represented as a number in JSON
    date: number; // Unix timestamp
    rate?: number; // Decimal is represented as a number in JSON
}

// Transaction type
export type Transaction =
    | { single: { entry: LedgerEntry } }
    | { trade: { spend: LedgerEntry; receive: LedgerEntry } }
    | { transfer: { from: LedgerEntry; to: LedgerEntry } };

// RefChange type
export type RefChange =
    | { create: { ref: Ref; wallet: string } }
    | { remove: { ref: Ref; wallet: string } }
    | { move: { ref: Ref; fromWallet: string; toWallet: string } }
    | { split: { originalRef: Ref; resultingRefs: Ref[]; wallet: string } }
    | { join: { originalRefs: Ref[]; resultingRef: Ref; wallet: string } }
    | { convert: { fromRefs: Ref[]; toRef: Ref; wallet: string } };

// BalanceChange type
export interface BalanceChange {
    transaction: Transaction;
    changes: RefChange[];
}
