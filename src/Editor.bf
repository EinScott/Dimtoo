using System;
using Pile;

namespace Dimtoo
{
	class Editor : Game
	{
		/// This is for returning overridden editors which load assets,
		/// have actual functionality and can load the scene provided with
		/// the needed registration. startScene might be null!
		public static function Editor(String startScene) createCustomEditor;

		bool debugRender;
		SpriteFont font; // Set this
		
		public Batch2D batch = new .() ~ delete _;
		public Scene scene = new .() ~ delete _;

		protected this(SpriteFont font)
		{
			Commands.sceneFocus = scene;
			this.font = font;
		}

		protected override void Update()
		{
			if (Input.Keyboard.Down(.F1))
			{
				debugRender = !debugRender;
				if (debugRender)
					DevConsole.ForceFocus();
			}

			if (debugRender && font != null)
				DevConsole.Update();
		}

		protected override void Render()
		{
			Graphics.Clear(System.Window, .Black);

			if (debugRender)
			{
				Perf.Render(batch, font);
				if (font != null)
					DevConsole.Render(batch, font, .(0, (.)System.Window.Height / 2, System.Window.Width, System.Window.Height));
			}
		}
	}
}
