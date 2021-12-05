using Dimtoo;
using System;
using System.IO;

namespace Pile
{
	extension Commands
	{
		public static Scene sceneFocus;

		static mixin CheckFocus()
		{
			if (sceneFocus == null)
			{
				Log.Error("No scene set as command focus");
				return;
			}
		}	

		[Description("Saves the scene to file")]
		public static void SceneSave(StringView name)
		{
			CheckFocus!();

			let save = scope String();
			sceneFocus.SerializeScene(save);

			let path = Path.InternalCombine(.. scope .(System.UserPath.Length + 16), System.UserPath, "saves");

			if (!Directory.Exists(path))
				Directory.CreateDirectory(path);
			path..Append(Path.DirectorySeparatorChar).Append(name);

			if (!path.EndsWith(".dscene"))
				path.Append(".dscene");

			if (File.Exists(path))
			{
				Log.Error("Scene file with that name already exists");
				return;
			}	

			if (File.WriteAllText(path, save) case .Err)
			{
				Log.Error("Failed to save file");
			}
		}

		[Description("Saves the scene to file")]
		public static void SceneSaveOverride(StringView name)
		{
			CheckFocus!();

			let save = scope String();
			sceneFocus.SerializeScene(save);

			let path = Path.InternalCombine(.. scope .(System.UserPath.Length + 16), System.UserPath, "saves");

			if (!Directory.Exists(path))
				Directory.CreateDirectory(path);
			path..Append(Path.DirectorySeparatorChar).Append(name);

			if (!path.EndsWith(".dscene"))
				path.Append(".dscene");

			if (File.WriteAllText(path, save) case .Err)
			{
				Log.Error("Failed to save file");
			}
		}

		[Description("Lists all files in the scene save dir")]
		public static void SceneListSaves()
		{
			let list = scope String("Scene save files: ");
			for (let file in Directory.EnumerateFiles(Path.InternalCombine(.. scope .(System.UserPath.Length + 16), System.UserPath, "saves")))
			{
				file.GetFileName(list);
				list.Append(", ");
			}

			if (list.EndsWith(", "))
				list.RemoveFromEnd(2);

			Log.Info(list);
		}

		[Description("Clear & load the scene from a save file")]
		public static void SceneLoad(StringView name)
		{
			CheckFocus!();

			let path = Path.InternalCombine(.. scope .(System.UserPath.Length + 16), System.UserPath, "saves");

			if (!Directory.Exists(path))
			{
				Log.Error("No saves found");
				return;
			}

			path..Append(Path.DirectorySeparatorChar).Append(name);
			if (!path.EndsWith(".dscene"))
				path.Append(".dscene");

			let save = scope String();
			if (File.ReadAllText(path, save) case .Err)
			{
				Log.Error("Error reading save file");
				return;
			}

			sceneFocus.DeserializeScene(save);
		}

		[Description("Toggles the editor, if there is one")]
		public static void Editor()
		{
			String currentScene = null;
			if (sceneFocus != null)
				sceneFocus.SerializeScene(currentScene = scope:: .());

			if (Core.Game is Editor)
				Core.SwapGame(Core.Config.createGame());
			else
			{
				if (Editor.createCustomEditor != null)
					Core.SwapGame(Editor.createCustomEditor(currentScene));
				else Log.Error("Editor.createCustomEditor function not set!");
			}
		}
	}
}
