﻿//************************************************************************************************
// Copyright © 2020 Steven M Cohn.  All rights reserved.
//************************************************************************************************

namespace River.OneMoreAddIn.Commands
{
	using River.OneMoreAddIn.Colorizer;
	using System.Collections.Generic;
	using System.Linq;
	using System.Xml.Linq;


	internal class ColorizeCommand : Command
	{
		public ColorizeCommand()
		{
		}


		public override void Execute(params object[] args)
		{
			var colorizer = new Colorizer(args[0] as string);

			using (var one = new OneNote(out var page, out var ns))
			{
				var updated = false;

				var runs = page.Root.Descendants(ns + "T")
					.Where(e => e.Attributes().Any(a => a.Name == "selected" && a.Value == "all"));

				if (runs != null)
				{
					foreach (var run in runs.ToList())
					{
						var cdata = run.GetCData();

						if (cdata.Value.Contains("<br>"))
						{
							// special handling to expand soft line breaks (Shift + Enter) and
							// split the line into multiple ines...

							var text = cdata.GetWrapper().Value;
							var lines = text.Split(new char[] { '\n' });

							// update current cdata with first line
							cdata.Value = colorizer.ColorizeOne(lines[0]);

							// collect subsequent lines from soft-breaks
							var elements = new List<XElement>();
							for (int i = 1; i < lines.Length; i++)
							{
								elements.Add(new XElement(ns + "OE",
									run.Parent.Attributes(),
									new XElement(ns + "T",
										new XCData(colorizer.ColorizeOne(lines[i]))
									)));
							}

							run.Parent.AddAfterSelf(elements);

							updated = true;
						}
						else
						{
							cdata.Value = colorizer.ColorizeOne(cdata.GetWrapper().Value);
							updated = true;
						}
					}

					if (updated)
					{
						one.Update(page);
					}
				}
			}
		}
	}
}
