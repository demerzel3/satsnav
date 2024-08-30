import fs from "fs";
import { BalanceChange, RefChange, Transaction } from "./types";
import { buildGraph } from "./buildGraph";
import { generateDOT } from "./generateDOT";
import forceAtlas2 from "graphology-layout-forceatlas2";
import { combineBaseCurrencyConversions } from "./combineBaseCurrencyConversions";

const parseBalanceChanges = (json: string): BalanceChange[] => {
    return JSON.parse(json) as BalanceChange[];
};

const balanceChanges = parseBalanceChanges(fs.readFileSync("./data.json"));
const graph = buildGraph(balanceChanges.slice(0, 350));
fs.writeFileSync("./graph.dot", generateDOT(graph.graph));

const removedGraph = combineBaseCurrencyConversions(graph);
// forceAtlas2.assign(graph.graph, { iterations: 50 });
// fs.writeFileSync("./public/graph.json", JSON.stringify(graph.graph.export()));

if (removedGraph) {
    fs.writeFileSync("./graph-removed.dot", generateDOT(removedGraph));
}
