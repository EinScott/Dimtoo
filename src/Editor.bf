using System;
using System.Diagnostics;
using Pile;

namespace Dimtoo
{
	abstract class Editor : Game
	{
		/// This is for returning overridden editors which load assets,
		/// have actual functionality and can load the scene provided with
		/// the needed registration. startScene might be null!
		public static function Editor(String startScene) createCustomEditor;
	}
}
