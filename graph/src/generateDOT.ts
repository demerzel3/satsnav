import { AssetType } from "./types";
import { BalanceGraph, EdgeAttributes, NodeAttributes } from "./BalanceGraph";

export function generateDOT(graph: BalanceGraph): string {
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