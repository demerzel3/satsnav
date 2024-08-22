import Graph from "graphology";
import { Attributes } from "graphology-types";
import { Ref, TransactionType } from "./types";

export type NodeAttributes =
    | {
          ref: Ref;
          wallet: string;
          transactionType?: TransactionType;
      }
    | {
          shape: "point" | "diamond";
          id: number;
      };

export interface EdgeAttributes extends Attributes {
    label?: string;
    tooltip: string;
}

export class BalanceGraph {
    #lastShapeId = 0;
    graph: Graph<NodeAttributes, EdgeAttributes>;

    constructor() {
        this.graph = new Graph<NodeAttributes, EdgeAttributes>();
    }

    addNode(id: string, attributes: NodeAttributes) {
        this.graph.mergeNode(id, attributes);
    }

    addEdge(from: string, to: string, attributes: EdgeAttributes) {
        this.graph.mergeEdge(from, to, attributes);
    }

    getNode(id: string) {
        return this.graph.getNodeAttributes(id);
    }

    getParentNode(id: string): NodeAttributes | undefined {
        const inNeighbors = this.graph.inNeighbors(id);

        return inNeighbors.length > 0
            ? this.getNode(inNeighbors[0])
            : undefined;
    }

    getParentNodeId(id: string): string | undefined {
        const parent = this.getParentNode(id);
        if (parent && "ref" in parent) {
            return `${parent.wallet}-${parent.ref.id}`;
        }
    }

    addRefNode(ref: Ref, wallet: string, transactionType?: TransactionType) {
        const nodeId = `${wallet}-${ref.id}`;
        this.addNode(nodeId, { ref, wallet, transactionType });
    }

    addRemoveEdge(
        ref: Ref,
        wallet: string,
        transactionType: TransactionType,
        transactionTooltip: string
    ) {
        if (transactionType === "Fee") {
            return;
        }

        const nodeId = `${wallet}-${ref.id}`;
        this.#lastShapeId += 1;
        const shapeId = `shape_${this.#lastShapeId}`;

        this.graph.addNode(shapeId, {
            shape: transactionType === "Withdrawal" ? "diamond" : "point",
            id: this.#lastShapeId,
        });
        this.addEdge(nodeId, shapeId, {
            label: transactionType,
            tooltip: transactionTooltip,
        });
    }

    addMoveEdge(
        ref: Ref,
        fromWallet: string,
        toWallet: string,
        transactionTooltip: string
    ) {
        const fromId = `${fromWallet}-${ref.id}`;
        const toId = `${toWallet}-${ref.id}`;

        this.addEdge(fromId, toId, {
            label: "Transfer",
            tooltip: transactionTooltip,
        });
    }

    addConvertEdges(
        fromRefs: Ref[],
        toRef: Ref,
        wallet: string,
        transactionTooltip: string
    ) {
        const toId = `${wallet}-${toRef.id}`;

        fromRefs.forEach((fromRef) => {
            const fromId = `${wallet}-${fromRef.id}`;
            this.addEdge(fromId, toId, {
                label: "Convert",
                tooltip: transactionTooltip,
            });
        });
    }

    addJoinEdges(
        fromRefs: Ref[],
        toRef: Ref,
        wallet: string,
        transactionTooltip: string
    ) {
        const toId = `${wallet}-${toRef.id}`;

        fromRefs.forEach((fromRef) => {
            const fromId = `${wallet}-${fromRef.id}`;
            this.addEdge(fromId, toId, {
                label: "Join",
                tooltip: transactionTooltip,
            });
        });
    }

    addSplitNodes(originalRef: Ref, resultingRefs: Ref[], wallet: string) {
        const originalNodeId = `${wallet}-${originalRef.id}`;
        const parentNode = this.getParentNode(originalNodeId);
        const parentNodeId = this.getParentNodeId(originalNodeId);

        if (
            parentNode &&
            parentNodeId &&
            "ref" in parentNode &&
            this.graph.getEdgeAttributes(parentNodeId, originalNodeId).label ===
                "Split"
        ) {
            // If the parent is already a split, add the new nodes as a split from the parent
            // and delete the intermediate ref node
            this.graph.dropNode(originalNodeId);
            resultingRefs.forEach((resultingRef) => {
                const resultingNodeId = `${wallet}-${resultingRef.id}`;
                this.addRefNode(resultingRef, wallet);
                this.addEdge(parentNodeId, resultingNodeId, {
                    label: "Split",
                    tooltip: `Split from ${originalRef.amount} ${originalRef.asset.name} to ${resultingRef.amount} ${resultingRef.asset.name}`,
                });
            });
        } else {
            resultingRefs.forEach((resultingRef) => {
                const resultingNodeId = `${wallet}-${resultingRef.id}`;
                this.addRefNode(resultingRef, wallet);
                this.addEdge(originalNodeId, resultingNodeId, {
                    label: "Split",
                    tooltip: `Split from ${originalRef.amount} ${originalRef.asset.name} to ${resultingRef.amount} ${resultingRef.asset.name}`,
                });
            });
        }
    }
}
