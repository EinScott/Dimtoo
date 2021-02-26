using Pile;
using System.IO;
using System.Collections;
using System;
using System.Diagnostics;

namespace Dimtoo
{
	[RegisterImporter]
	public class AsepriteImporter : Importer
	{
		public String Name => "ase";

		public Result<void> Load(StringView name, Span<uint8> data)
		{
			let mem = scope MemoryStream();
			Try!(mem.TryWrite(data));
			mem.Position = 0;

			let ase = scope Aseprite(mem);

			let frames = scope List<Sprite.Frame>();
			let frameName = scope String();
			int i = 0;
			for (let frame in ase.Frames)
			{
				// Frame texture name
				frameName.Set(name);
				i.ToString(frameName);
				let subTex = Importers.SubmitTextureAsset(frameName, frame.Bitmap);

				// Add frame
				frames.Add(new Sprite.Frame(subTex, frame.Duration));
				i++;
			}

			let animations = scope List<Sprite.Animation>();
			for (let tag in ase.Tags)
				animations.Add(new Sprite.Animation(tag.Name, tag.From, tag.To));

			Point2 origin = .Zero;
			for (let slice in ase.Slices)
				if (slice.Name == "origin" && slice.Pivot != null)
				{
					origin = slice.Pivot.Value;
				}

			Importers.SubmitAsset(name, new Sprite(frames, animations, origin));

			return .Ok;
		}

		public Result<uint8[]> Build(Span<uint8> data, Span<StringView> config, StringView dataFilePath)
		{
			let outData = new uint8[data.Length];
			data.CopyTo(outData);
			return outData; // For now, just save the whole aseprite file, later move stuff from up there to here
		}
	}
}
