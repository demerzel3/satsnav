import fs from "fs";
import { BalanceChange, RefChange, Transaction } from "./types";
import { generateDOT } from "./generateDOT";

const parseBalanceChanges = (json: string): BalanceChange[] => {
    return JSON.parse(json) as BalanceChange[];
};

const balanceChanges = parseBalanceChanges(fs.readFileSync("./data.json"));
const dot = generateDOT(balanceChanges.slice(0, 10));
fs.writeFileSync("./graph.dot", dot);
