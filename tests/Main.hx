package tests;

import tests.TestBase;
import tests.FunctionTest;
import tests.ShipTest;

class Main {
	public static function main() {
		// Basic
		new TestBase('./yarns/Basic.json').start();
		// Expression
		new TestBase('./yarns/Expressions.json', './yarns/testcases/Expressions.testplan').start();
		// Function
		new FunctionTest().start();
		// Ship
		new ShipTest().start();
	}
}
