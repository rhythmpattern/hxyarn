package hxyarn.compiler;

import haxe.ds.GenericStack;
import haxe.Exception;
import hxyarn.compiler.Token.TokenType;

class Scanner {
	var source:String;
	var tokens:Array<Token> = new Array<Token>();
	var indents = new GenericStack<Int>();

	var start:Int = 0;
	var current:Int = 0;
	var line:Int = 1;

	var keywords = new Map<String, TokenType>();

	var mode = new GenericStack<ScannerMode>();

	public function new(source:String) {
		this.source = source;

		keywords.set("or", OPERATOR_LOGICAL_OR);
		keywords.set("and", OPERATOR_LOGICAL_AND);
		keywords.set("is", OPERATOR_LOGICAL_EQUALS);
		keywords.set("eq", OPERATOR_LOGICAL_EQUALS);
		keywords.set("lt", OPERATOR_LOGICAL_LESS);
		keywords.set("lte", OPERATOR_LOGICAL_LESS_THAN_EQUALS);
		keywords.set("gt", OPERATOR_LOGICAL_GREATER);
		keywords.set("gte", OPERATOR_LOGICAL_GREATER_THAN_EQUALS);
		keywords.set("not", OPERATOR_LOGICAL_NOT);
		keywords.set("neq", OPERATOR_LOGICAL_NOT_EQUALS);
		keywords.set("xor", OPERATOR_LOGICAL_XOR);
		keywords.set("false", KEYWORD_FALSE);
		keywords.set("true", KEYWORD_TRUE);
		keywords.set("null", KEYWORD_NULL);
		keywords.set("to", OPERATOR_ASSIGNMENT);
		keywords.set("as", EXPRESSION_AS);
	}

	public static function scan(source:String) {
		return new Scanner(source).scanTokens();
	}

	function scanTokens():Array<Token> {
		while (!isAtEnd()) {
			start = current;
			scanToken();
		}

		tokens.push(new Token(EOF, "", null, line, ""));
		return tokens;
	}

	function scanToken() {
		var c = advance();

		if (!mode.isEmpty()) {
			switch (mode.first()) {
				case BodyMode:
					bodyMode(c);
				case HeaderMode:
					headerMode(c);
				case TextMode:
					textMode(c);
				case HashtagMode:
					hashtagMode(c);
				case TextCommandOrHashtagMode:
					textCommandOrHashtagMode(c);
				case TextEscapedMode:
					textEscapedMode(c);
				case ExpressionMode:
					expressionMode(c);
				case CommandMode:
					commandMode(c);
				case CommandTextMode:
					commandTextMode(c);
				case CommandIdOrExpressionMode:
					commandIdOrExpressionMode(c);
				case CommandIdMode:
					commandIdMode(c);
				case JumpOptionMode:
					jumpOptionMode(c);
				case JumpOptionTextMode:
					jumpOptionTextMode(c);
			}
		} else {
			rootMode(c);
		}
	}

	function rootMode(c:String) {
		switch (c) {
			case ' ':
			case '\t':
			case '\r':
				match('\n'); // consume newlines for windows
				newLine();
			case '\n':
				// TODO figure out whitespace channels
				newLine();
			case '-':
				if (match("-") && match("-")) {
					addToken(BODY_START);
					mode.add(BodyMode);
				} else {
					throw new Exception('Unexpected char at line $line: $c');
				}
			case ':':
				addToken(HEADER_DELIMITER);
				consumeWhitespace();
				mode.add(HeaderMode);
			case '#':
				addToken(HASHTAG);
				mode.add(HashtagMode);
			case _:
				if (isAlpha(c)) {
					identifier(ID);
					return;
				}
				throw new Exception('Unexpected char at line $line: $c');
		}
	}

	function headerMode(c:String) {
		switch (c) {
			case ' ':
			case '\r':
				match('\n'); // consume newlines for windows
				newLine();
				// addToken(NEWLINE); TODO: figure out newline channel
				mode.pop();
			case '\n':
				// addToken(NEWLINE); TODO: figure out newline channel
				newLine();
				mode.pop();
			case _:
				restOfTheLine(true);
				mode.pop();
		}
	}

	function bodyMode(c:String) {
		switch (c) {
			case ' ': // skip
			case '\t': // skip
			case '\r':
				match('\n'); // consume newlines for windows
				newLine();
			// addToken(NEWLINE); TODO: figure out newline channel
			case '\n':
				newLine();
			// addToken(NEWLINE); TODO: figure out newline channel
			case '/': // commnet
				if (match('/')) {
					restOfTheLine(false); // TODO: figure out comment channel
				}
			case '=': // Body end
				if (match('=') && match('=')) {
					addToken(BODY_END);
					mode.pop();
					return;
				}

				addToken(TEXT, c);
				mode.add(TextMode);
			case '-': // Shortcut arrow
				if (match(">")) {
					addToken(SHORTCUT_ARROW);
					return;
				}

				addToken(TEXT, c);
				mode.add(TextMode);
			case '<':
				if (match("<")) {
					mode.add(CommandMode);
					addToken(COMMAND_START);
					return;
				}

				addToken(TEXT, c);
				mode.add(TextMode);
			case '[':
				if (match('[')) {
					addToken(JUMP_OPTION_START);
					mode.add(JumpOptionMode);
					mode.add(JumpOptionTextMode);
					return;
				}

				addToken(TEXT, c);
				mode.add(TextMode);
			case '#':
				addToken(HASHTAG);
				mode.add(TextCommandOrHashtagMode);
				mode.add(HashtagMode);
			case '{':
				addToken(EXPRESSION_START);
				mode.add(TextMode);
				mode.add(ExpressionMode);
			case _:
				addToken(TEXT, c);
				mode.add(TextMode);
		}
	}

	function textMode(c:String) {
		switch (c) {
			case '\r':
				match('\n');
				newLine(true);
				mode.pop();
			case '\n':
				newLine(true);
				mode.pop();
			case '\\':
				if (match('[') || match(']')) {
					addToken(TEXT);
					return;
				}

				mode.add(TextEscapedMode);
			case '#':
				addToken(HASHTAG);
				mode.pop(); // popping to replace current mode
				mode.add(TextCommandOrHashtagMode);
				mode.add(HashtagMode);
			case '{':
				addToken(EXPRESSION_START);
				mode.add(ExpressionMode);
			case '[':
				if (match('[')) {
					addToken(JUMP_OPTION_START);
					mode.add(JumpOptionMode);
					mode.add(JumpOptionTextMode);
				}
				text();
			case '<':
				if (match('<')) {
					addToken(COMMAND_START);
					// Popping to actually switch to text command mode before going to command mode
					mode.pop();
					mode.add(TextCommandOrHashtagMode);
					mode.add(CommandMode);
				} else {
					restOfTheLine(true);
				}
			case '/':
				match('/') ? restOfTheLine() : text();
			case _:
				text();
		}
	}

	function textEscapedMode(c:String) {
		switch (c) {
			case '\\':
				addToken(TEXT, c);
				mode.pop();
			case '<':
				addToken(TEXT, c);
				mode.pop();
			case '>':
				addToken(TEXT, c);
				mode.pop();
			case '{':
				addToken(TEXT, c);
				mode.pop();
			case '}':
				addToken(TEXT, c);
				mode.pop();
			case '#':
				addToken(TEXT, c);
				mode.pop();
			case '/':
				addToken(TEXT, c);
				mode.pop();
			case _:
				throw 'Unexpected char at line $line: $c';
		}
	}

	function textCommandOrHashtagMode(c:String) {
		switch (c) {
			// whitespace
			case ' ':
			case '\t':
			case '\r':
				match('\n'); // consume newlines for windows
				newLine(true);
				mode.pop();
			case '\n':
				newLine(true);
				mode.pop();
			case '/':
				if (match('/'))
					restOfTheLine(); // TODO figure out comment channel
			case '<':
				if (match('<')) {
					addToken(COMMAND_START);
					mode.add(CommandMode);
				}
			case '#':
				addToken(HASHTAG);
				mode.add(HashtagMode);
			case _:
				throw new Exception('Unexpected char at line $line: $c');
		}
	}

	function hashtagMode(c:String) {
		switch (c) {
			case ' ':
			case '\t':
			case '#':
				addToken(HASHTAG);
			case _:
				// TODO Hashtag texts actually stop on whitespace
				restOfTheLine(true, HASHTAG_TEXT);
				mode.pop();
		}
	}

	function expressionMode(c:String) {
		switch (c) {
			case ' ':
			case '\t':
			case '=':
				match('=') ? addToken(OPERATOR_LOGICAL_EQUALS) : addToken(OPERATOR_ASSIGNMENT);
			case '$':
				identifier();
			case '<':
				match('=') ? addToken(OPERATOR_LOGICAL_LESS_THAN_EQUALS) : addToken(OPERATOR_LOGICAL_LESS);
			case '>':
				if (match('=')) {
					addToken(OPERATOR_LOGICAL_GREATER_THAN_EQUALS);
				} else if (match('>')) {
					addToken(COMMAND_END);
					mode.pop();
					mode.pop();
				} else {
					addToken(OPERATOR_LOGICAL_GREATER);
				}
			case '!':
				match('=') ? addToken(OPERATOR_LOGICAL_NOT_EQUALS) : addToken(OPERATOR_LOGICAL_NOT);
			case '&':
				match('&') ? addToken(OPERATOR_LOGICAL_AND) : throw 'Expected & at line $line after $c';
			case '|':
				match('|') ? addToken(OPERATOR_LOGICAL_OR) : throw 'Expected | at line $line after $c';
			case '^':
				addToken(OPERATOR_LOGICAL_XOR);
			case '+':
				match('=') ? addToken(OPERATOR_MATHS_ADDITION_EQUALS) : addToken(OPERATOR_MATHS_ADDITION);
			case '-':
				match('=') ? addToken(OPERATOR_MATHS_SUBTRACTION_EQUALS) : addToken(OPERATOR_MATHS_SUBTRACTION);
			case '*':
				match('=') ? addToken(OPERATOR_MATHS_MULTIPLICATION_EQUALS) : addToken(OPERATOR_MATHS_MULTIPLICATION);
			case '%':
				match('=') ? addToken(OPERATOR_MATHS_MODULUS_EQUALS) : addToken(OPERATOR_MATHS_MODULUS);
			case '/':
				match('=') ? addToken(OPERATOR_MATHS_DIVISION_EQUALS) : addToken(OPERATOR_MATHS_DIVISION);
			case '(':
				addToken(LPAREN);
			case ')':
				addToken(RPAREN);
			case ',':
				addToken(COMMA);
			case '}':
				addToken(EXPRESSION_END);
				mode.pop();
			case '.':
				addToken(DOT);
			case "\"":
				string();
			case _:
				if (isDigit(c)) {
					number();
					return;
				}

				if (isAlpha(c)) {
					identifier(FUNC_ID);
					return;
				}

				throw new Exception('Unexpected char at line $line: $c');
		}
	}

	function commandMode(c:String) {
		switch (c) {
			case ' ':
			case '\t':
			case '>':
				if (match('>')) {
					addToken(COMMAND_END);
					mode.pop();
					return;
				}
				throw 'Unexpected char at line $line: $c';
			case _:
				command();
		}
	}

	function commandTextMode(c:String) {
		switch (c) {
			case '>':
				if (match('>')) {
					addToken(COMMAND_TEXT_END);
					mode.pop();
					return;
				}
				throw 'Unexpected char at line $line: $c';

			case '{':
				addToken(COMMAND_EXPRESSION_START);
				mode.add(ExpressionMode);
			case _:
				commandText();
		}
	}

	function commandIdOrExpressionMode(c:String) {
		switch (c) {
			case '>':
				if (match('>')) {
					addToken(COMMAND_END);
					mode.pop();
					return;
				}
				throw 'Unexpected char at line $line: $c';
			case '{':
				addToken(EXPRESSION_START);
				mode.pop(); // Pop the just switch modes
				mode.add(ExpressionMode);
			case _:
				identifier(ID);
				mode.pop();
		}
	}

	function commandIdMode(c:String) {
		switch (c) {
			case '{':
				addToken(EXPRESSION_START);
				mode.pop();
				mode.add(ExpressionMode);
			case '>':
				if (match('>')) {
					addToken(COMMAND_END);
					mode.pop();
					return;
				}
				throw 'Unexpected char at line $line: $c';
			case _:
				identifier(ID);
				mode.pop();
		}
	}

	function jumpOptionTextMode(c:String) {
		switch (c) {
			case '|':
				addToken(JUMP_OPTION_LINK);
				mode.pop();
			case ']':
				throw 'Unexpected char at line $line: $c';
			case '{':
				addToken(COMMAND_EXPRESSION_START);
				mode.add(ExpressionMode);
			case _:
				jumpOptionText();
		}
	}

	function jumpOptionText() {
		while (peek() != ']' && peek() != '|' && peek() != '{' && !isAtEnd()) {
			advance();
		}

		var value = source.substr(start, current - start);
		addToken(TEXT, value);
	}

	function jumpOptionMode(c:String) {
		switch (c) {
			case ']':
				if (match(']')) {
					addToken(JUMP_OPTION_END);
					mode.pop();
					return;
				}
				throw 'Unexpected char at line $line: $c';
			case '{':
				throw 'Unexpected char at line $line: $c';
			case _:
				jumpOption();
		}
	}

	function jumpOption() {
		while (peek() != ']' && peek() != '{' && !isAtEnd()) {
			advance();
		}

		var value = source.substr(start, current - start);
		addToken(JUMP_OPTION_LINK, value);
	}

	function text() {
		while (continueTextFrag()) {
			advance();
		}

		var value = source.substr(start, current - start);
		addToken(TEXT, value);
	}

	function continueTextFrag():Bool {
		if (peek() == '<' && peekNext() == '<')
			return false;

		if (peek() == '/' && peekNext() == '/')
			return false;

		if (peek() == '\r')
			return false;
		if (peek() == '\n')
			return false;
		if (peek() == '#')
			return false;
		if (peek() == '{')
			return false;
		if (peek() == '[')
			return false;
		if (peek() == "\\")
			return false;

		return !isAtEnd();
	}

	function commandText() {
		while (peek() != '>' && peek() != '{' && !isAtEnd()) {
			advance();
		}

		var value = source.substr(start, current - start);
		addToken(COMMAND_TEXT, value);
	}

	function command() {
		while (peek() != ' ' && peek() != '>' && !isAtEnd()) {
			advance();
		}

		var value = source.substr(start, current - start);
		switch (value) {
			case "if":
				addToken(COMMAND_IF);
				consumeWhitespace();
				mode.add(ExpressionMode);
			case "elseif":
				addToken(COMMAND_ELSEIF);
				consumeWhitespace();
				mode.add(ExpressionMode);
			case "else":
				addToken(COMMAND_ELSE);
				consumeWhitespace();
			case "set":
				addToken(COMMAND_SET);
				consumeWhitespace();
				mode.add(ExpressionMode);
			case "endif":
				addToken(COMMAND_ENDIF);
			case "call":
				addToken(COMMAND_CALL);
				consumeWhitespace();
				mode.add(ExpressionMode);
			case "declare":
				addToken(COMMAND_DECLARE);
				consumeWhitespace();
				mode.add(ExpressionMode);
			case "jump":
				addToken(COMMAND_JUMP);
				consumeWhitespace();
				mode.add(CommandIdOrExpressionMode);
			case "case":
				addToken(COMMAND_CASE);
				consumeWhitespace();
				mode.add(CommandIdMode);
			case "enum":
				addToken(COMMAND_ENUM);
				mode.add(CommandIdMode);
			case "endenum":
				addToken(COMMAND_ENDENUM);
				consumeWhitespace();
			case "local":
				addToken(COMMAND_LOCAL);
				consumeWhitespace();
			case _:
				addToken(COMMAND_TEXT);
				mode.pop(); // popping to replace current mode
				mode.add(CommandTextMode);
		}
	}

	function isAtEnd():Bool {
		return current >= source.length;
	}

	function advance():String {
		current++;

		// Taken from StringTools
		#if utf16
		var c = YarnStringTools.utf16CodePointAt(source, current - 1);
		if (c >= YarnStringTools.MIN_SURROGATE_CODE_POINT) {
			current++;
		}

		return String.fromCharCode(c);
		#else
		throw new Exception('Most support UTF16');
		#end
	}

	function match(expected:String):Bool {
		if (isAtEnd())
			return false;
		if (String.fromCharCode(YarnStringTools.utf16CodePointAt(source, current)) != expected)
			return false;

		current++;
		return true;
	}

	function previous():Token {
		return tokens[tokens.length - 1];
	}

	function peek():String {
		if (isAtEnd())
			return "\\0";
		return String.fromCharCode(YarnStringTools.utf16CodePointAt(source, current));
	}

	function peekNext() {
		if (current + 1 >= source.length)
			return '\\0';
		return String.fromCharCode(YarnStringTools.utf16CodePointAt(source, current + 1));
	}

	function string() {
		while (peek() != '"' && !isAtEnd()) {
			if (peek() == '\n')
				line++;
			advance();
		}

		if (isAtEnd()) {
			throw new Exception('Unterminated string at line $line');
		}

		advance();
		var value = source.substr(start + 1, current - 2 - start);
		addToken(STRING, value);
	}

	function restOfTheLine(asToken:Bool = false, token:TokenType = REST_OF_LINE) {
		while (peek() != '\n' && peek() != '\r' && !isAtEnd()) {
			advance();
		}

		if (asToken) {
			var value = source.substr(start, current - start);
			addToken(token, value);
		}
	}

	function consumeWhitespace() {
		while (!isAtEnd() && match(' ')) {}
	}

	function number() {
		while (isDigit(peek()))
			advance();

		if (peek() == '.' && isDigit(peekNext())) {
			advance();

			while (isDigit(peek()))
				advance();
		}

		addToken(TokenType.NUMBER, Std.parseFloat(source.substr(start, current - start)));
	}

	function identifier(tokenType:TokenType = VAR_ID) {
		while (isAlphaNumeric(peek()))
			advance();

		var text = source.substr(start, current - start);

		var type = keywords.get(text);
		if (type == null)
			type = tokenType;

		addToken(type, text);
	}

	function addToken(type:TokenType, ?literal:Dynamic = null) {
		var text = source.substr(start, current - start);
		tokens.push(new Token(type, text, literal, line, ""));
	}

	function isDigit(c:String):Bool {
		return c >= '0' && c <= '9';
	}

	var alpha:EReg = new EReg("^[a-zA-Z_$]+$","i");

	var id_head:EReg = new EReg("^[a-zA-Z_$\u00A8\u00AA\u00AD\u00AF\u00B2-\u00B5\u00B7-\u00BA\u00BC-\u00BE\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u00FF\u0100-\u02FF\u0370-\u167F\u1681-\u180D\u180F-\u1DBF\u1E00-\u1FFF\u200B-\u200D\u202A-\u202E\u203F-\u2040\u2054\u2060-\u206F\u2070-\u20CF\u2100-\u218F\u2460-\u24FF\u2776-\u2793\u2C00-\u2DFF\u2E80-\u2FFF\u3004-\u3007\u3021-\u302F\u3031-\u303F\u3040-\uD7FF\uF900-\uFD3D\uFD40-\uFDCF\uFDF0-\uFE1F\uFE30-\uFE44\uFE47-\uFFFD]+$","i");

	function isAlpha(c:String):Bool {
		if (id_head.match(c))
			return true;

		// Emoji stuff seems like regex in haxe doesn't support UTF16 so we'll do it manually
		var code = new UnicodeString(c).charCodeAt(0);
		return code > 0x10000 && code < 0x1FFFD || code > 0x20000 && code < 0x2FFFD || code > 0x30000 && code < 0x3FFFD || code > 0x40000 && code < 0x4FFFD
			|| code > 0x50000 && code < 0x5FFFD || code > 0x60000 && code < 0x6FFFD || code > 0x70000 && code < 0x7FFFD || code > 0x80000 && code < 0x8FFFD
			|| code > 0x90000 && code < 0x9FFFD || code > 0xA0000 && code < 0xAFFFD || code > 0xB0000 && code < 0xBFFFD || code > 0xC0000 && code < 0xCFFFD
			|| code > 0xD0000 && code < 0xDFFFD;
	}

	function isAlphaNumeric(c:String):Bool {
		return isAlpha(c) || isDigit(c);
	}

	function newLine(?storeToken:Bool = false) {
		line++;
		var currentLenght = lengthOfIndent();

		if (storeToken) {
			var value = source.substr(start + 1, current - 2 - start);
			addToken(NEWLINE, value);
		}

		var previousIndent:Int;
		if (this.indents.isEmpty()) {
			previousIndent = 0;
		} else {
			previousIndent = this.indents.first();
		}

		if (currentLenght > previousIndent) {
			this.indents.add(currentLenght);
			addToken(INDENT, '<indent to $currentLenght>');
		} else if (currentLenght < previousIndent) {
			while (currentLenght < previousIndent) {
				previousIndent = this.indents.pop();
				addToken(DEDENT, '<dedent from $previousIndent>');

				if (!this.indents.isEmpty()) {
					previousIndent = this.indents.first();
				} else {
					previousIndent = 0;
				}
			}
		}
	}

	function lengthOfIndent():Int {
		var length = 0;
		var sawSpaces = false;
		var sawTabs = false;

		while (peek() == ' ' || peek() == '\t') {
			if (match(' ')) {
				length += 1;
				sawSpaces = true;
			}

			if (match('\t')) {
				length += 8;
				sawTabs = true;
			}
		}

		if (sawSpaces && sawTabs)
			throw new Exception('Cannot mix spaces and tabs');

		return length;
	}
}

enum ScannerMode {
	BodyMode;
	HeaderMode;
	HashtagMode;
	TextMode;
	TextCommandOrHashtagMode;
	TextEscapedMode;
	ExpressionMode;
	CommandMode;
	CommandTextMode;
	CommandIdOrExpressionMode;
	CommandIdMode;
	JumpOptionMode;
	JumpOptionTextMode;
}
