// Loads ../main.js with `require("obsidian")` answered by the fake.
const Module = require("module");
const path = require("path");
const fake = require("./fake-obsidian");
const load = Module._load;
Module._load = function (request, ...rest) {
  return request === "obsidian" ? fake : load.call(this, request, ...rest);
};
module.exports = require(path.join(__dirname, "..", "main.js"));
