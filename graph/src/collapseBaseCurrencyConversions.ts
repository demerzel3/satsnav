import { bidirectional } from "graphology-shortest-path";
import toUndirected from "graphology-operators/to-undirected";
import { BalanceGraph, NodeAttributes } from "./BalanceGraph";
import { Ref } from "./types";

export function collapseBaseCurrencyConversions(graph: BalanceGraph) {
    const g = graph.graph;
    const pathG = toUndirected(graph.graph);
    let pickN = 5;
    const anchorNodeId = g.findNode((nodeId) => {
        const inEdgeIds = g.inEdges(nodeId);
        const node = g.getNodeAttributes(nodeId);

        // Not a conversion
        if (
            inEdgeIds.length !== 1 ||
            g.getEdgeAttribute(inEdgeIds[0], "label") !== "Convert"
        ) {
            return false;
        }

        // Not base currency
        if (!("ref" in node) || node.ref.asset.name !== "EUR") {
            return false;
        }

        return --pickN === 0;
    });

    if (!anchorNodeId) return;

    const anchorNode = g.getNodeAttributes(anchorNodeId);
    console.log("Conversion to EUR", nodeToString(anchorNode));

    // Trace everything related to this conversion back to the last time this was in EUR
    // console.log(
    //     `Conversion to EUR - ${refToString(
    //         refChange.convert.toRef
    //     )}`
    // );

    const visitedNodes: Set<string> = new Set([anchorNodeId]);
    const nodesToVisit: string[] = g.inNeighbors(anchorNodeId);
    const nodesToVisitSet: Set<string> = new Set(nodesToVisit);

    while (nodesToVisit.length > 0) {
        const nodeId = nodesToVisit.pop()!;
        nodesToVisitSet.delete(nodeId);
        const node = graph.getNode(nodeId);

        if (!("ref" in node)) {
            continue;
        }

        visitedNodes.add(nodeId);

        if (
            node.ref.asset.name === "EUR" &&
            !g.someInNeighbor(nodeId, (inNodeId) => visitedNodes.has(inNodeId))
        ) {
            // console.log("Found EUR", nodeToString(node));
            // sourceNodes.add(nodeId);
            continue;
        }

        // const path = bidirectional(g, nodeId, anchorNodeId);
        // // if (!path) {
        // //     console.log("!! Not connected with anchor", nodeToString(node));
        // //     break;
        // // }
        // path?.forEach((pathNodeId) => {
        //     if (
        //         pathNodeId === nodeId ||
        //         visitedNodes.has(pathNodeId) ||
        //         nodesToVisitSet.has(pathNodeId)
        //     ) {
        //         return;
        //     }

        //     console.log(
        //         "New node found via path!!",
        //         nodeToString(g.getNodeAttributes(pathNodeId))
        //     );
        //     nodesToVisit.push(pathNodeId);
        //     nodesToVisitSet.add(pathNodeId);
        // });

        if (node.ref.asset.name !== "EUR" || g.outDegree(nodeId) > 1) {
            g.outNeighbors(nodeId).forEach((outNodeId) => {
                if (
                    visitedNodes.has(outNodeId) ||
                    nodesToVisitSet.has(outNodeId)
                ) {
                    return;
                }

                nodesToVisit.push(outNodeId);
                nodesToVisitSet.add(outNodeId);
            });
        }

        const parentIds = g.inNeighbors(nodeId);

        // No more parents to look at and this is not EUR, failed to combine nodes
        // if (parentIds.length === 0) {
        //     // Make sure nodesToVisit is not empty as this is our failure check
        //     nodesToVisit.push(nodeId);
        //     nodesToVisitSet.add(nodeId);
        //     break;
        // }

        parentIds.forEach((parentNodeId) => {
            if (
                visitedNodes.has(parentNodeId) ||
                nodesToVisitSet.has(parentNodeId)
            ) {
                return;
            }

            nodesToVisit.push(parentNodeId);
            nodesToVisitSet.add(parentNodeId);
        });

        if (nodesToVisit.length !== nodesToVisitSet.size) {
            console.log(nodesToVisit);
            console.log([...nodesToVisitSet]);
            throw new Error("Male male");
        }
    }

    visitedNodes.forEach((nodeId) => {
        g.mergeNode(nodeId, { wallet: "Collapsible" });
    });

    if (nodesToVisit.length === 0) {
        console.log("SUCCESS", visitedNodes.size, "visited");
        // TODO: compute source and terminal nodes
        visitedNodes.forEach((nodeId) => {
            console.log("---", nodeToString(graph.getNode(nodeId)));
        });
    } else {
        // console.log("FAIL", visitedNodes.length, "visited");
    }
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
