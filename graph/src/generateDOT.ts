import {
    BalanceChange,
    RefChange,
    Ref,
    AssetType,
    LedgerEntryType,
} from "./types";

export function generateDOT(changes: BalanceChange[]): string {
    const refIds = new Map<string, string>();
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

    function getRefId(ref: Ref, wallet: string): string {
        const key = `${wallet}-${ref.asset.name}-${ref.amount}-${ref.date}`;
        if (!refIds.has(key)) {
            refIds.set(key, `ref_${refIds.size}`);
        }
        return refIds.get(key)!;
    }

    function escapeLabel(label: string): string {
        return label.replace(/"/g, '\\"');
    }

    function generateRefNode(ref: Ref, wallet: string): string {
        const id = getRefId(ref, wallet);
        const color = getColor(wallet);
        const label = escapeLabel(`${ref.amount} ${ref.asset.name}`);
        const tooltip = escapeLabel(
            `Wallet: ${wallet}, Asset: ${ref.asset.name}, Amount: ${ref.amount}`
        );
        return `  ${id} [label="${label}", color="${color}", style=filled, tooltip="${tooltip}"];\n`;
    }

    function generateTransactionTooltip(
        transaction: BalanceChange["transaction"]
    ): string {
        if ("single" in transaction) {
            return `Single: ${LedgerEntryType[transaction.single.entry.type]}`;
        } else if ("trade" in transaction) {
            return `Trade: ${transaction.trade.spend.amount} ${transaction.trade.spend.asset.name} -> ${transaction.trade.receive.amount} ${transaction.trade.receive.asset.name}`;
        } else {
            return `Transfer: ${transaction.transfer.from.amount} ${transaction.transfer.from.asset.name} from ${transaction.transfer.from.wallet} to ${transaction.transfer.to.wallet}`;
        }
    }

    function generateChangeEdge(
        change: RefChange,
        transactionTooltip: string
    ): string {
        if ("create" in change) {
            return ""; // No edge for create
        } else if ("remove" in change) {
            const { ref, wallet } = change.remove;
            const fromId = getRefId(ref, wallet);
            return `  ${fromId} -> point_${fromId} [label="Remove", tooltip="${transactionTooltip}"];\n  point_${fromId} [shape=point];\n`;
        } else if ("move" in change) {
            const { ref, fromWallet, toWallet } = change.move;
            const fromId = getRefId(ref, fromWallet);
            const toId = getRefId(ref, toWallet);
            return `  ${fromId} -> ${toId} [label="Move", tooltip="${transactionTooltip}"];\n`;
        } else if ("split" in change) {
            const { originalRef, resultingRefs, wallet } = change.split;
            const fromId = getRefId(originalRef, wallet);
            const toIds = resultingRefs.map((ref) => getRefId(ref, wallet));
            return toIds
                .map(
                    (toId) =>
                        `  ${fromId} -> ${toId} [label="Split", tooltip="${transactionTooltip}"];\n`
                )
                .join("");
        } else {
            const { fromRefs, toRef, wallet } = change.convert;
            const fromIds = fromRefs.map((ref) => getRefId(ref, wallet));
            const toId = getRefId(toRef, wallet);
            return fromIds
                .map(
                    (fromId) =>
                        `  ${fromId} -> ${toId} [label="Convert", tooltip="${transactionTooltip}"];\n`
                )
                .join("");
        }
    }

    let dot = "digraph BalanceChanges {\n";
    dot += "  rankdir=LR;\n";
    dot += "  node [shape=box];\n\n";

    let rankGroups: Map<number, string[]> = new Map();

    changes.forEach((change, index) => {
        const timestamp =
            "single" in change.transaction
                ? change.transaction.single.entry.date
                : "trade" in change.transaction
                ? change.transaction.trade.spend.date
                : change.transaction.transfer?.from.date;

        if (!rankGroups.has(timestamp)) {
            rankGroups.set(timestamp, []);
        }

        const transactionTooltip = escapeLabel(
            generateTransactionTooltip(change.transaction)
        );

        change.changes.forEach((refChange) => {
            if ("create" in refChange) {
                dot += generateRefNode(
                    refChange.create.ref,
                    refChange.create.wallet
                );
                rankGroups
                    .get(timestamp)!
                    .push(
                        getRefId(refChange.create.ref, refChange.create.wallet)
                    );
            } else if ("remove" in refChange) {
                dot += generateRefNode(
                    refChange.remove.ref,
                    refChange.remove.wallet
                );
                rankGroups
                    .get(timestamp)!
                    .push(
                        getRefId(refChange.remove.ref, refChange.remove.wallet)
                    );
            } else if ("move" in refChange) {
                dot += generateRefNode(
                    refChange.move.ref,
                    refChange.move.fromWallet
                );
                dot += generateRefNode(
                    refChange.move.ref,
                    refChange.move.toWallet
                );
                rankGroups
                    .get(timestamp)!
                    .push(
                        getRefId(refChange.move.ref, refChange.move.toWallet)
                    );
            } else if ("split" in refChange) {
                dot += generateRefNode(
                    refChange.split.originalRef,
                    refChange.split.wallet
                );
                refChange.split.resultingRefs.forEach((ref) => {
                    dot += generateRefNode(ref, refChange.split.wallet);
                    rankGroups
                        .get(timestamp)!
                        .push(getRefId(ref, refChange.split.wallet));
                });
            } else {
                refChange.convert.fromRefs.forEach((ref) => {
                    dot += generateRefNode(ref, refChange.convert.wallet);
                });
                dot += generateRefNode(
                    refChange.convert.toRef,
                    refChange.convert.wallet
                );
                rankGroups
                    .get(timestamp)!
                    .push(
                        getRefId(
                            refChange.convert.toRef,
                            refChange.convert.wallet
                        )
                    );
            }

            dot += generateChangeEdge(refChange, transactionTooltip);
        });

        dot += "\n";
    });

    // Add rank constraints
    rankGroups.forEach((nodes, timestamp) => {
        if (nodes.length > 0) {
            dot += `  { rank=same; ${nodes.join("; ")} }\n`;
        }
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
