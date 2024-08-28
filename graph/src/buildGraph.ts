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
                const fromIds = refChange.convert.fromRefs.map((ref) =>
                    graph.addRefNode(
                        ref,
                        refChange.convert.wallet,
                        transactionType
                    )
                );
                if (refChange.convert.toRef.asset.name === "EUR") {
                    // Trace everything related to this conversion back to the last time this was in EUR
                    // console.log(
                    //     `Conversion to EUR - ${refToString(
                    //         refChange.convert.toRef
                    //     )}`
                    // );

                    const visitedNodes: string[] = [];
                    const baseCurrencyNodes: string[] = [];
                    const nodesToVisit: string[] = fromIds;

                    while (nodesToVisit.length > 0) {
                        const nodeId = nodesToVisit.pop()!;
                        const node = graph.getNode(nodeId);

                        if (!("ref" in node)) {
                            continue;
                        }

                        visitedNodes.push(nodeId);

                        if (node.ref.asset.name === "EUR") {
                            // console.log("Found EUR", nodeToString(node));
                            baseCurrencyNodes.push(nodeId);
                            continue;
                        }

                        if (graph.graph.outDegree(nodeId) > 1) {
                            // console.log(
                            //     "More than 1 child, aborting",
                            //     nodeToString(node)
                            // );
                            // Make sure nodesToVisit is not empty as this is our failure check
                            nodesToVisit.push(nodeId);
                            break;
                        }

                        // No more parents to look at and this is not EUR, failed to combine nodes
                        const parentIds = graph.graph.inNeighbors(nodeId);
                        if (parentIds.length === 0) {
                            // Make sure nodesToVisit is not empty as this is our failure check
                            nodesToVisit.push(nodeId);
                            break;
                        }

                        // Recursively look at parents
                        // console.log(
                        //     "Looking at",
                        //     parentIds.length,
                        //     "more nodes"
                        // );
                        Array.prototype.push.apply(nodesToVisit, parentIds);
                    }

                    if (nodesToVisit.length === 0) {
                        console.log(
                            "SUCCESS",
                            visitedNodes.length,
                            "visited,",
                            baseCurrencyNodes.length,
                            "base nodes found"
                        );
                        visitedNodes.forEach((nodeId) => {
                            console.log(
                                "---",
                                nodeToString(graph.getNode(nodeId))
                            );
                        });
                    } else {
                        // console.log("FAIL", visitedNodes.length, "visited");
                    }
                }
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

const nodeToString = (node: NodeAttributes): string => {
    if ("shape" in node) {
        return `${node.id} - ${node.shape}`;
    }

    return `${node.wallet}-${refToString(node.ref)}`;
};

const refToString = (ref: Ref): string => {
    return `${ref.id} ${ref.amount} ${ref.asset.name}`;
};
