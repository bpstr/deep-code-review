import ts from "typescript";
const program = ts.createProgram(["src.ts"], {});
console.log(program.getSourceFiles().length);
