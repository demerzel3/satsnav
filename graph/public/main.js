import serializedGraph from "./graph.json" with { type: "json" };

// Create a graphology graph
const graph = new graphology.Graph();
graph.import(serializedGraph)

// Instantiate sigma.js and render the graph
const sigmaInstance = new Sigma(graph, document.getElementById("container"));
