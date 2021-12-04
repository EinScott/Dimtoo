using Dimtoo;
using System;
using System.IO;

namespace Pile
{
	extension Commands
	{
		static Scene sceneFocus;

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

			let path = Path.InternalCombine(.. scope .(System.DataPath.Length + 16), System.DataPath, "saves");

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

			let path = Path.InternalCombine(.. scope .(System.DataPath.Length + 16), System.DataPath, "saves");

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
			for (let file in Directory.EnumerateFiles(Path.InternalCombine(.. scope .(System.DataPath.Length + 16), System.DataPath, "saves")))
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

			// TODO:
		}
	}
}
