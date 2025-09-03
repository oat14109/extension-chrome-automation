using System;
using System.IO;
using System.Text;
using System.Text.Json;
using System.DirectoryServices.AccountManagement;

class Msg { public string cmd { get; set; } = string.Empty; }

class Program {
  static void Main() {
    Console.InputEncoding = new UTF8Encoding(false);
    Console.OutputEncoding = new UTF8Encoding(false);
    var stdin = Console.OpenStandardInput();
    while (true) {
      var lenBytes = ReadExact(stdin, 4);
      if (lenBytes == null) break;
      int len = BitConverter.ToInt32(lenBytes, 0);
      var buf = ReadExact(stdin, len);
      if (buf == null) break;
      try {
        var req = JsonSerializer.Deserialize<Msg>(buf);
        string? user = GetAdSamAccountName() ?? Environment.UserName;
        WriteMessage(new { ok = true, username = user });
      } catch {
        WriteMessage(new { ok = false, username = "" });
      }
    }
  }

  static byte[]? ReadExact(Stream s, int n) {
    var ms = new MemoryStream();
    var buf = new byte[4096];
    int need = n, read;
    while (need > 0 && (read = s.Read(buf, 0, Math.Min(buf.Length, need))) > 0) { ms.Write(buf, 0, read); need -= read; }
    if (need != 0) return null; return ms.ToArray();
  }

  static void WriteMessage(object obj) {
    var json = JsonSerializer.Serialize(obj);
    var b = Encoding.UTF8.GetBytes(json);
    var len = BitConverter.GetBytes(b.Length);
    var stdout = Console.OpenStandardOutput();
    stdout.Write(len, 0, 4); stdout.Write(b, 0, b.Length); stdout.Flush();
  }

  static string? GetAdSamAccountName() {
    try {
      using var ctx = new PrincipalContext(ContextType.Domain);
      var up = UserPrincipal.Current;
      if (up != null && !string.IsNullOrWhiteSpace(up.SamAccountName)) return up.SamAccountName;
    } catch { }
    return null;
  }
}
