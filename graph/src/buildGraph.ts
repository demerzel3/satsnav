import {
    BalanceChange,
    LedgerEntryType,
    Ref,
    Transaction,
    TransactionType,
} from "./types";
import { BalanceGraph, NodeAttributes } from "./BalanceGraph";

function getTransactionType(transaction: Transaction): TransactionType {
    if ("single" in transaction) {
        return LedgerEntryType[
            transaction.single.entry.type
        ] as keyof typeof LedgerEntryType;
    } else if ("trade" in transaction) {
        return "Trade";
    } else {
        return "Transfer";
    }
}

function generateTransactionTooltip(transaction: Transaction): string {
    if ("single" in transaction) {
        return `Single: ${LedgerEntryType[transaction.single.entry.type]}`;
    } else if ("trade" in transaction) {
        return `Trade: ${transaction.trade.spend.amount} ${transaction.trade.spend.asset.name} -> ${transaction.trade.receive.amount} ${transaction.trade.receive.asset.name}`;
    } else {
        return `Transfer: ${transaction.transfer.from.amount} ${transaction.transfer.from.asset.name} from ${transaction.transfer.from.wallet} to ${transaction.transfer.to.wallet}`;
    }
}

export function buildGraph(changes: BalanceChange[]): BalanceGraph {
    const graph = new BalanceGraph();

    changes.forEach((change) => {
        const transactionType = getTransactionType(change.transaction);
        const transactionTooltip = generateTransactionTooltip(
            change.transaction
        );

        change.changes.forEach((refChange) => {
            if ("create" in refChange) {
                graph.addRefNode(refChange.create.ref, refChange.create.wallet);
            } else if ("remove" in refChange) {
                graph.addRefNode(
                    refChange.remove.ref,
                    refChange.remove.wallet,
                    transactionType
                );
                graph.addRemoveEdge(
                    refChange.remove.ref,
                    refChange.remove.wallet,
                    transactionType,
                    transactionTooltip
                );
            } else if ("move" in refChange) {
                if (refChange.move.fromWallet !== refChange.move.toWallet) {
                    graph.addRefNode(
                        refChange.move.ref,
                        refChange.move.fromWallet
                    );
                    graph.addRefNode(
                        refChange.move.ref,
                        refChange.move.toWallet
                    );
                    graph.addMoveEdge(
                        refChange.move.ref,
                        refChange.move.fromWallet,
                        refChange.move.toWallet,
                        transactionTooltip
                    );
                }
            } else if ("split" in refChange) {
                graph.addRefNode(
                    refChange.split.originalRef,
                    refChange.split.wallet
                );
                graph.addSplitNodes(
                    refChange.split.originalRef,
                    refChange.split.resultingRefs,
                    refChange.split.wallet
                );
            } else if ("join" in refChange) {
                refChange.join.originalRefs.forEach((ref) => {
                    graph.addRefNode(
                        ref,
                        refChange.join.wallet,
                        transactionType
                    );
                });
                graph.addJoinNodes(
                    refChange.join.originalRefs,
                    refChange.join.resultingRef,
                    refChange.join.wallet
                );
            } else {
                refChange.convert.fromRefs.map((ref) =>
                    graph.addRefNode(
                        ref,
                        refChange.convert.wallet,
                        transactionType
                    )
                );
                graph.addRefNode(
                    refChange.convert.toRef,
                    refChange.convert.wallet
                );
                graph.addConvertEdges(
                    refChange.convert.fromRefs,
                    refChange.convert.toRef,
                    refChange.convert.wallet,
                    transactionTooltip
                );
            }
        });
    });

    return graph;
}
