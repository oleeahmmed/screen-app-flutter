using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;

class ScreenshotTool
{
    static void Main(string[] args)
    {
        try
        {
            if (args.Length == 0)
            {
                Console.WriteLine("Usage: screenshot_tool.exe <output_path>");
                return;
            }

            string outputPath = args[0];
            
            // Get the size of the primary screen
            Rectangle bounds = Screen.PrimaryScreen.Bounds;
            
            // Create a bitmap to hold the screenshot
            using (Bitmap bitmap = new Bitmap(bounds.Width, bounds.Height))
            {
                // Create a graphics object from the bitmap
                using (Graphics graphics = Graphics.FromImage(bitmap))
                {
                    // Copy the screen to the bitmap
                    graphics.CopyFromScreen(Point.Empty, Point.Empty, bounds.Size);
                }
                
                // Save the bitmap as PNG
                bitmap.Save(outputPath, ImageFormat.Png);
            }
            
            Console.WriteLine("SUCCESS");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"ERROR:{ex.Message}");
        }
    }
}