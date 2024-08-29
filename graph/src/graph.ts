import fs from "fs";
import { BalanceChange, RefChange, Transaction } from "./types";
import { buildGraph } from "./buildGraph";
import { generateDOT } from "./generateDOT";
import forceAtlas2 from "graphology-layout-forceatlas2";
import { collapseBaseCurrencyConversions } from "./collapseBaseCurrencyConversions";

const parseBalanceChanges = (json: string): BalanceChange[] => {
    return JSON.parse(json) as BalanceChange[];
};

const balanceChanges = parseBalanceChanges(fs.readFileSync("./data.json"));
const graph = buildGraph(balanceChanges.slice(0, 300));
collapseBaseCurrencyConversions(graph);
// forceAtlas2.assign(graph.graph, { iterations: 50 });
// fs.writeFileSync("./public/graph.json", JSON.stringify(graph.graph.export()));

fs.writeFileSync("./graph.dot", generateDOT(graph));
