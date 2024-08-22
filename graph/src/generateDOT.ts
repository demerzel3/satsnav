import {
    BalanceChange,
    RefChange,
    Ref,
    AssetType,
    LedgerEntryType,
    Transaction,
    TransactionType,
} from "./types";
import { BalanceGraph, EdgeAttributes, NodeAttributes } from "./BalanceGraph";

function buildGraph(changes: BalanceChange[]): BalanceGraph {
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
                refChange.split.resultingRefs.forEach((ref, index, refs) => {
                    const isLast = index === refs.length - 1;
                    graph.addSplitNode(
                        refChange.split.originalRef,
                        ref,
                        refChange.split.wallet,
                        isLast ? transactionType : undefined
                    );
                });
            } else if ("join" in refChange) {
                refChange.join.originalRefs.forEach((ref) => {
                    graph.addRefNode(
                        ref,
                        refChange.join.wallet,
                        transactionType
                    );
                });
                graph.addRefNode(
                    refChange.join.resultingRef,
                    refChange.join.wallet
                );
                graph.addJoinEdges(
                    refChange.join.originalRefs,
                    refChange.join.resultingRef,
                    refChange.join.wallet,
                    transactionTooltip
                );
            } else {
                refChange.convert.fromRefs.forEach((ref) => {
                    graph.addRefNode(
                        ref,
                        refChange.convert.wallet,
                        transactionType
                    );
                });
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

function generateDOTFromGraph(graph: BalanceGraph): string {
    const idsMap = new Map<string, string>();
    let lastId = 0;
    const colorMap = new Map<string, string>();
    let colorIndex = 0;
    const colors = [
        "#FF6B6B",
        "#4ECDC4",
        "#45B7D1",
        "#FFA07A",
        "#98D8C8",
        "#F06292",
        "#AED581",
        "#7986CB",
        "#4DB6AC",
        "#9575CD",
    ];

    function getColor(wallet: string): string {
        if (!colorMap.has(wallet)) {
            colorMap.set(wallet, colors[colorIndex % colors.length]);
            colorIndex++;
        }
        return colorMap.get(wallet)!;
    }

    function getNodeIdDOT(graphId: string): string {
        // Special case for shapes
        if (graphId.startsWith("shape_")) return graphId;

        const existingDotId = idsMap.get(graphId);
        if (existingDotId) return existingDotId;

        lastId += 1;
        const newDotId = `ref_${lastId}`;
        idsMap.set(graphId, newDotId);

        return newDotId;
    }

    function generateNodeDOT(id: string, node: NodeAttributes): string {
        // Simple case: shapes!
        // TODO: should probably be derived from an attribute or something...
        if ("shape" in node) {
            return `  ${getNodeIdDOT(id)} [shape=${node.shape}];\n`;
        }

        const { ref, wallet, transactionType } = node;

        // Escape special characters in the label
        const escapeLabel = (label: string) => label.replace(/"/g, '\\"');

        const formatAmountFixed = (
            amount: number,
            decimalPlaces: number
        ): string => {
            return amount.toFixed(decimalPlaces).replace(/\.?0+$/, "");
        };

        // Format amount based on asset type
        const formatAmount = (amount: number, assetType: AssetType): string => {
            const formattedValue =
                assetType === AssetType.Crypto
                    ? formatAmountFixed(amount, 6)
                    : formatAmountFixed(amount, 2);
            if (formattedValue === "0") {
                return formatAmountFixed(amount, 12);
            }

            return formattedValue;
        };

        // Format rate
        const formatRate = (rate: number | undefined): string => {
            return rate !== undefined ? rate.toFixed(2) : "-";
        };

        if (!ref) {
            console.log(id, node);
        }

        const formattedAmount = formatAmount(ref.amount, ref.asset.type);
        const formattedRate = formatRate(ref.rate);
        const isFee = transactionType === "Fee";

        // Determine node color
        const color = isFee ? "#D3D3D3" : getColor(wallet); // Light gray for fee, otherwise use wallet color

        // Construct label
        let label = `<<font point-size="${isFee ? 10 : 14}">${escapeLabel(
            `${formattedAmount} ${ref.asset.name}`
        )}</font>`;
        if (ref.asset.name !== "EUR") {
            label += `<BR/><font point-size="10">${escapeLabel(
                `Rate: ${formattedRate}`
            )}</font>`;
        }
        label += ">";

        // Construct tooltip
        const tooltip = escapeLabel(
            `Wallet: ${wallet}, Asset: ${ref.asset.name}, Amount: ${formattedAmount}, Rate: ${formattedRate}`
        );

        return `  ${getNodeIdDOT(
            id
        )} [label=${label}, color="${color}", style=filled, tooltip="${tooltip}"];\n`;
    }

    function generateEdgeDOT(
        from: string,
        to: string,
        edge: EdgeAttributes
    ): string {
        const { label, tooltip } = edge;

        let dot = `  ${getNodeIdDOT(from)} -> ${getNodeIdDOT(to)}`;

        if (label && label !== "Join" && label !== "Split") {
            dot += ` [label="${label}"`;
        } else {
            dot += " [";
        }

        if (tooltip) {
            dot += ` edgetooltip="${tooltip}"`;
        }

        dot += "];\n";

        return dot;
    }

    let dot = "digraph BalanceChanges {\n";
    dot += "  rankdir=LR;\n";
    dot += "  node [shape=box];\n\n";

    // Generate nodes
    graph.graph.forEachNode((nodeId, attributes) => {
        dot += generateNodeDOT(nodeId, attributes);
    });

    // Generate edges
    graph.graph.forEachEdge((edge, attributes, source, target) => {
        dot += generateEdgeDOT(source, target, attributes);
    });

    // Generate legend
    dot += "\n  // Legend\n";
    dot += "  subgraph cluster_legend {\n";
    dot += '    label = "Legend";\n';
    dot += "    style = filled;\n";
    dot += "    color = lightgrey;\n";

    colorMap.forEach((color, wallet) => {
        const legendId = `legend_${wallet.replace(/\s+/g, "_")}`;
        dot += `    ${legendId} [label="${wallet}", color="${color}", style=filled];\n`;
    });

    dot += "  }\n";

    dot += "}\n";
    return dot;
}

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

export function generateDOT(changes: BalanceChange[]): string {
    const graph = buildGraph(changes);
    return generateDOTFromGraph(graph);
}
