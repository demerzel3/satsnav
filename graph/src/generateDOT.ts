import {
    BalanceChange,
    RefChange,
    Ref,
    AssetType,
    LedgerEntryType,
    Transaction,
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

    function hasRefId(ref: Ref, wallet: string): boolean {
        const key = `${wallet}-${ref.id}`;

        return refIds.has(key);
    }

    function getRefId(ref: Ref, wallet: string): string {
        const key = `${wallet}-${ref.id}`;
        if (!refIds.has(key)) {
            refIds.set(key, `ref_${refIds.size}`);
        }
        return refIds.get(key)!;
    }

    function escapeLabel(label: string): string {
        return label.replace(/"/g, '\\"');
    }

    function formatAmount(amount: number, assetType: AssetType): string {
        const decimalPlaces = assetType === AssetType.Crypto ? 12 : 10;
        return amount.toFixed(decimalPlaces).replace(/\.?0+$/, "");
    }

    function formatRate(rate: number | undefined): string {
        return rate?.toFixed(2) ?? "-";
    }

    function generateRefNode(
        ref: Ref,
        wallet: string,
        transactionType?: TransactionType
    ): string {
        if (hasRefId(ref, wallet)) {
            return "";
        }

        const isFee = transactionType === "Fee";

        const id = getRefId(ref, wallet);
        const color = isFee ? "#D3D3D3" : getColor(wallet); // Light gray for fee
        const formattedAmount = formatAmount(ref.amount, ref.asset.type);
        const formattedRate = formatRate(ref.rate);

        // Using HTML-like label with <BR/> for line break
        const label = `<<font point-size="${isFee ? 10 : 14}">${escapeLabel(
            `${formattedAmount} ${ref.asset.name}`
        )}</font>${
            ref.asset.name !== "EUR"
                ? `<BR/><font point-size="10">${escapeLabel(
                      `Rate: ${formattedRate}`
                  )}</font>`
                : ""
        }>`;

        const tooltip = escapeLabel(
            `Wallet: ${wallet}, Asset: ${ref.asset.name}, Amount: ${formattedAmount}, Rate: ${formattedRate}`
        );

        return `  ${id} [label=${label}, color="${color}", style=filled, tooltip="${tooltip}"];\n`;
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

    type TransactionType = "Trade" | "Transfer" | keyof typeof LedgerEntryType;

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

    function generateChangeEdge(
        change: RefChange,
        transaction: Transaction,
        transactionTooltip: string
    ): string {
        if ("create" in change) {
            return ""; // No edge for create
        } else if ("remove" in change) {
            const { ref, wallet } = change.remove;
            const fromId = getRefId(ref, wallet);
            const transactionType = getTransactionType(transaction);
            if (transactionType === "Fee") {
                return ""; // No edge for fee removals
            } else if (transactionType === "Withdrawal") {
                return `  ${fromId} -> point_${fromId} [label="${transactionType}", edgetooltip="${transactionTooltip}"];\n  point_${fromId} [shape=diamond];\n`;
            } else {
                return `  ${fromId} -> point_${fromId} [label="${transactionType}", edgetooltip="${transactionTooltip}"];\n  point_${fromId} [shape=point];\n`;
            }
        } else if ("move" in change) {
            const { ref, fromWallet, toWallet } = change.move;
            const fromId = getRefId(ref, fromWallet);
            const toId = getRefId(ref, toWallet);
            return `  ${fromId} -> ${toId} [label="Transfer", edgetooltip="${transactionTooltip}"];\n`;
        } else if ("split" in change) {
            const { originalRef, resultingRefs, wallet } = change.split;
            const fromId = getRefId(originalRef, wallet);
            const toIds = resultingRefs.map((ref) => getRefId(ref, wallet));
            return toIds
                .map(
                    (toId) =>
                        `  ${fromId} -> ${toId} [edgetooltip="${transactionTooltip}"];\n`
                )
                .join("");
        } else if ("join" in change) {
            const { originalRefs, resultingRef, wallet } = change.join;
            const fromIds = originalRefs.map((ref) => getRefId(ref, wallet));
            const toId = getRefId(resultingRef, wallet);
            return fromIds
                .map(
                    (fromId) =>
                        `  ${fromId} -> ${toId} [edgetooltip="${transactionTooltip}"];\n`
                )
                .join("");
        } else {
            const { fromRefs, toRef, wallet } = change.convert;
            const fromIds = fromRefs.map((ref) => getRefId(ref, wallet));
            const toId = getRefId(toRef, wallet);
            return fromIds
                .map(
                    (fromId) =>
                        `  ${fromId} -> ${toId} [label="Convert", edgetooltip="${transactionTooltip}"];\n`
                )
                .join("");
        }
    }

    let dot = "digraph BalanceChanges {\n";
    dot += "  rankdir=LR;\n";
    dot += "  node [shape=box];\n\n";

    changes.forEach((change, index) => {
        const timestamp =
            "single" in change.transaction
                ? change.transaction.single.entry.date
                : "trade" in change.transaction
                ? change.transaction.trade.spend.date
                : change.transaction.transfer?.from.date;

        const transactionTooltip = escapeLabel(
            generateTransactionTooltip(change.transaction)
        );
        const transactionType = getTransactionType(change.transaction);

        change.changes.forEach((refChange) => {
            if ("create" in refChange) {
                dot += generateRefNode(
                    refChange.create.ref,
                    refChange.create.wallet
                );
            } else if ("remove" in refChange) {
                dot += generateRefNode(
                    refChange.remove.ref,
                    refChange.remove.wallet,
                    transactionType
                );
            } else if ("move" in refChange) {
                if (refChange.move.fromWallet === refChange.move.toWallet) {
                    return;
                }

                dot += generateRefNode(
                    refChange.move.ref,
                    refChange.move.fromWallet
                );
                dot += generateRefNode(
                    refChange.move.ref,
                    refChange.move.toWallet
                );
            } else if ("split" in refChange) {
                dot += generateRefNode(
                    refChange.split.originalRef,
                    refChange.split.wallet
                );
                refChange.split.resultingRefs.forEach((ref, index, refs) => {
                    const isLast = refs[index + 1] === undefined;
                    dot += generateRefNode(
                        ref,
                        refChange.split.wallet,
                        isLast ? transactionType : undefined
                    );
                });
            } else if ("join" in refChange) {
                refChange.join.originalRefs.forEach((ref) => {
                    dot += generateRefNode(ref, refChange.join.wallet);
                });
                dot += generateRefNode(
                    refChange.join.resultingRef,
                    refChange.join.wallet
                );
            } else {
                refChange.convert.fromRefs.forEach((ref) => {
                    dot += generateRefNode(
                        ref,
                        refChange.convert.wallet,
                        transactionType
                    );
                });
                dot += generateRefNode(
                    refChange.convert.toRef,
                    refChange.convert.wallet
                );
            }

            dot += generateChangeEdge(
                refChange,
                change.transaction,
                transactionTooltip
            );
        });

        dot += "\n";
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
