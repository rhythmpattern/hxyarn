package hxyarn.compiler;

import hxyarn.program.types.IType;
import hxyarn.program.Library;
import haxe.ds.BalancedTree;
import haxe.io.BufferInput;
import hxyarn.program.types.FunctionType;
import hxyarn.compiler.DeclarationVisitor.DeclaractionVisitor;
import hxyarn.program.types.BuiltInTypes;
import hxyarn.compiler.Stmt.StmtDialogue;
import hxyarn.program.Operand;
import hxyarn.program.Instruction;
import sys.FileSystem;
import hxyarn.program.Node;
import sys.io.File;
import hxyarn.program.Program;

class Compiler {
	var labelCount = 0;

	public var currentNode:Node;

	var rawTextNode = false; // TODO
	var program:Program;
	var fileName:String;

	public function new(fileName:String) {
		program = new Program();
		this.fileName = fileName;
	}

	public static function compileText(text:String, name:String, ?library:Library):CompilationResult {
		return handleYarn(text, name, library);
	}

	public static function compileFile(path:String, ?library:Library):CompilationResult {
		var string = File.read(path).readAll().toString();
		var directories = FileSystem.absolutePath(path).split('/');
		var fileName = directories[directories.length - 1];

		return handleYarn(string, fileName, library);
	}

	static function handleYarn(yarn:String, fileName:String, ?library:Library):CompilationResult {
		var compiler = new Compiler(fileName);

		return compiler.compileYarn(yarn, library);
	}

	function compileYarn(yarn:String, ?library:Library):CompilationResult {
		var tokens = Scanner.scan(yarn);
		var dialogue = new StmtParser(tokens).parse();

		var stringTableManager = new StringTableManager();

		var derivedVariableDeclarations = new Array<Declaration>();
		var knownVariableDeclarations = new Array<Declaration>();
		var typeDelaractions = BuiltInTypes.all;

		if (library != null) {
			// TODO Diagnotsics
			var declarations = getDeclaractionsFromLibrary(library);
			knownVariableDeclarations = knownVariableDeclarations.concat(declarations);
		}

		registerStrings(fileName, stringTableManager, dialogue);

		for (node in dialogue.nodes) {
			currentNode = new Node();
			for (header in node.headers) {
				if (header.id.lexeme == "title") {
					currentNode.name = StringTools.trim(header.value.lexeme);
				}
				if (header.id.lexeme == "tags") {
					var tags = [];
					if (header.value != null)
						tags = header.value.lexeme.split(',');

					currentNode.tags.concat(tags);
				}
			}
			currentNode.labels.set(registerLabel(), currentNode.instructions.length);
			var declaractionVisitor = new DeclaractionVisitor(fileName, knownVariableDeclarations, typeDelaractions);
			declaractionVisitor.visitNode(node);
			derivedVariableDeclarations = derivedVariableDeclarations.concat(declaractionVisitor.newDeclarations);
			knownVariableDeclarations = knownVariableDeclarations.concat(declaractionVisitor.newDeclarations);
			var checker = new TypeCheckVisitor(fileName, knownVariableDeclarations, typeDelaractions);
			checker.visitNode(node);
			derivedVariableDeclarations = derivedVariableDeclarations.concat(checker.newDeclarations);
			knownVariableDeclarations = knownVariableDeclarations.concat(checker.newDeclarations);
			var visitor = new CodeGenerationVisitor(this);
			visitor.visitNode(node);
			var hasRemainingOptions = false;
			for (instruction in currentNode.instructions) {
				if (instruction.opcode == OpCode.ADD_OPTIONS)
					hasRemainingOptions = true;

				if (instruction.opcode == OpCode.SHOW_OPTIONS)
					hasRemainingOptions = false;
			}

			if (hasRemainingOptions) {
				emit(OpCode.SHOW_OPTIONS, []);
				emit(OpCode.RUN_NODE, []);
			} else {
				emit(OpCode.STOP, []);
			}

			program.nodes.set(currentNode.name, currentNode);
		}

		var results = new CompilationResult();
		results.program = program;
		results.stringTable = stringTableManager.stringTable;

		for (declaration in knownVariableDeclarations) {
			if (Std.isOfType(declaration.type, FunctionType))
				continue;

			if (declaration.type == BuiltInTypes.undefined)
				continue;

			var value:Operand;

			if (declaration.defaultValue == null) {
				// TODO: Diagnostic
				continue;
			}

			if (declaration.type == BuiltInTypes.string) {
				value = Operand.fromString(declaration.defaultValue);
			} else if (declaration.type == BuiltInTypes.number) {
				value = Operand.fromFloat(cast(declaration.defaultValue, Float));
			} else if (declaration.type == BuiltInTypes.boolean) {
				value = Operand.fromBool(cast(declaration.defaultValue, Bool));
			} else {
				throw 'Cannot create an initial value for type ${declaration.type.name}';
			}

			results.program.initialValues.set(declaration.name, value);
		}

		results.declarations = derivedVariableDeclarations;

		return results;
	}

	function registerStrings(fileName:String, stringTableManager:StringTableManager, dialogue:StmtDialogue) {
		var visitor = new StringTableGeneratorVisitor(fileName, stringTableManager, this);
		visitor.visitDialogue(dialogue);
	}

	public function emit(opCode:OpCode, operands:Array<Operand>) {
		var instruction = new Instruction();
		instruction.opcode = opCode;
		instruction.operands = operands;

		currentNode.instructions.push(instruction);
	}

	public function getLineIdTag(hashtags:Array<String>):String {
		if (hashtags == null)
			return null;

		for (hashtag in hashtags) {
			if (StringTools.startsWith(hashtag, "line:"))
				return hashtag;
		}

		return null;
	}

	public function registerLabel(?commentary:String = null) {
		return 'L${labelCount++}$commentary';
	}

	function getDeclaractionsFromLibrary(library:Library):Array<Declaration> {
		var declarations = new Array<Declaration>();

		for (func in library.functions) {
			// we don't handle non built in types here
			if (!Std.isOfType(func.returnType, IType))
				continue;

			var functionType = new FunctionType();
			var includeMethod = true;

			// TODO Param Types
			for (i in 0...func.paramCount)
				functionType.parameters.push(BuiltInTypes.any);

			functionType.returnType = func.returnType;

			var decl = new Declaration();
			decl.name = func.name;
			decl.type = functionType;
			decl.sourceFileLine = -1;
			decl.sourceNodeLine = -1;
			decl.sourceFileName = "External";

			declarations.push(decl);
		}

		return declarations;
	}
}
