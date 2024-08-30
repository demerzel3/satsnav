import { bidirectional } from "graphology-shortest-path";
import toUndirected from "graphology-operators/to-undirected";
import { BalanceGraph, EdgeAttributes, NodeAttributes } from "./BalanceGraph";
import { Ref } from "./types";
import Graph from "graphology";
import subgraph from "graphology-operators/subgraph";

export function combineBaseCurrencyConversions(graph: BalanceGraph): Graph<NodeAttributes, EdgeAttributes> | undefined {
    const nodeIdToString = (nodeId: string): string => nodeToString(graph.getNode(nodeId));

    const g = graph.graph;
    const pathG = toUndirected(graph.graph);
    let pickN = 3;
    const anchorNodeId = g.findNode((nodeId) => {
        const inEdgeIds = g.inEdges(nodeId);
        const node = g.getNodeAttributes(nodeId);

        // Not a conversion
        if (inEdgeIds.length !== 1 || g.getEdgeAttribute(inEdgeIds[0], "label") !== "Convert") {
            return false;
        }

        // Not base currency
        if (!("ref" in node) || node.ref.asset.name !== "EUR") {
            return false;
        }

        return --pickN === 0;
    });

    if (!anchorNodeId) return;

    console.log("Conversion to EUR", nodeIdToString(anchorNodeId));

    const visitedNodes: Set<string> = new Set([anchorNodeId]);
    const nodesToVisit: string[] = g.inNeighbors(anchorNodeId);
    const nodesToVisitSet: Set<string> = new Set(nodesToVisit);

    const visit = () => {
        while (nodesToVisit.length > 0) {
            const nodeId = nodesToVisit.pop()!;
            nodesToVisitSet.delete(nodeId);
            const node = graph.getNode(nodeId);

            // TODO: revisit this to keep track of withdrawals, single trades and such
            if (!("ref" in node)) {
                continue;
            }

            visitedNodes.add(nodeId);

            // Stop iteration on EUR nodes with no visited parents
            if (
                node.ref.asset.name === "EUR" &&
                (g.inDegree(nodeId) === 1 || !g.someInNeighbor(nodeId, (inNodeId) => visitedNodes.has(inNodeId)))
            ) {
                // console.log("Found EUR", nodeToString(node));
                // sourceNodes.add(nodeId);
                continue;
            }

            // TODO: if outDegree is 0 and not EUR and with rate we should fail
            if (node.ref.asset.name !== "EUR" || g.outDegree(nodeId) > 1) {
                g.outNeighbors(nodeId).forEach((outNodeId) => {
                    if (visitedNodes.has(outNodeId) || nodesToVisitSet.has(outNodeId)) {
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
                if (visitedNodes.has(parentNodeId) || nodesToVisitSet.has(parentNodeId)) {
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
    };

    const getEdgeNodes = (): [sourceNodes: Set<string>, terminalNodes: Set<string>] => {
        const sourceNodes: Set<string> = new Set();
        const terminalNodes: Set<string> = new Set();
        visitedNodes.forEach((nodeId) => {
            // No inbound nodes at all, or no visited ones
            if (!g.someInNeighbor(nodeId, (inNodeId) => visitedNodes.has(inNodeId))) {
                sourceNodes.add(nodeId);
                return;
            }
            // No outbound nodes at all, or no visited ones
            if (!g.someOutNeighbor(nodeId, (outNodeId) => visitedNodes.has(outNodeId))) {
                terminalNodes.add(nodeId);
                return;
            }
        });

        return [sourceNodes, terminalNodes];
    };

    while (nodesToVisit.length > 0) {
        visit();
        // Process terminated early, was not possible to simplify
        if (nodesToVisit.length > 0) {
            return;
        }

        const [sourceNodes, terminalNodes] = getEdgeNodes();
        let path: string[] | null = null;
        for (const terminalNodeId of terminalNodes) {
            for (const sourceNodeId of sourceNodes) {
                path = bidirectional(g, terminalNodeId, sourceNodeId);
                if (path) break;
            }
            if (path) break;
        }

        if (path) {
            console.log("Path found!", path.map(nodeIdToString));

            path.forEach((pathNodeId) => {
                if (visitedNodes.has(pathNodeId)) return;

                nodesToVisit.push(pathNodeId);
                nodesToVisitSet.add(pathNodeId);
            });
        }
    }

    const [sourceNodes, terminalNodes] = getEdgeNodes();
    console.log("SUCCESS", visitedNodes.size, "visited", sourceNodes.size, "sources", terminalNodes.size, "terminals");
    sourceNodes.forEach((nodeId) => {
        console.log("s---", nodeIdToString(nodeId));
    });
    console.log();
    terminalNodes.forEach((nodeId) => {
        console.log("t---", nodeIdToString(nodeId));
    });

    const combinedGraph = subgraph(g, visitedNodes);

    const [combineNodeId] = g.mergeNode("shape-combine", {
        shape: "diamond",
    });
    visitedNodes.forEach((visitedNodeId) => {
        if (sourceNodes.has(visitedNodeId)) {
            g.mergeEdge(visitedNodeId, combineNodeId);
        } else if (terminalNodes.has(visitedNodeId)) {
            g.mergeEdge(combineNodeId, visitedNodeId);
        } else {
            g.dropNode(visitedNodeId);
        }
    });

    // visitedNodes.forEach((nodeId) => {
    //     g.mergeNode(nodeId, { wallet: "Collapsible" });
    // });

    return combinedGraph;
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
