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

			let ase = scope Aseprite();
			Try!(ase.Parse(mem));

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
				frames.Add(Sprite.Frame(subTex, frame.Duration));
				i++;
			}

			let animations = scope List<(String name, Sprite.Animation anim)>();
			for (let tag in ase.Tags)
				animations.Add((new String(tag.Name), Sprite.Animation(tag.From, tag.To)));

			Point2 origin = .Zero;
			for (let slice in ase.Slices)
				if (slice.Name == "origin" && slice.Pivot != null)
				{
					origin = slice.Pivot.Value;
				}

			let asset = new Sprite(frames, animations, origin);
			if (Importers.SubmitAsset(name, asset) case .Ok)
				return .Ok;
			else
			{
				delete asset;
				return .Err;
			}
		}

		public Result<uint8[]> Build(Stream data, Span<StringView> config, StringView dataFilePath)
		{
			return Importer.TryStreamToArray!(data);
		}
	}
}
