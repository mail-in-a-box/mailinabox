#!/usr/bin/python3
#
# Generate documentation for how this machine works by
# parsing our bash scripts!

import cgi, re
import markdown
from modgrammar import *

def generate_documentation():
	print("""<!DOCTYPE html>
<html>
    <head>
        <meta charset="utf-8">
        <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">
        <meta name="viewport" content="width=device-width">

        <title>Build Your Own Mail Server From Scratch</title>

        <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.2.0/css/bootstrap.min.css">
        <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.2.0/css/bootstrap-theme.min.css">

        <style>
		    @import url(https://fonts.googleapis.com/css?family=Iceland);
		    @import url(https://fonts.googleapis.com/css?family=Raleway:400,700);
			@import url(https://fonts.googleapis.com/css?family=Ubuntu:300,500);
		   	body {
		    		font-family: Raleway, sans-serif;
		    		font-size: 16px;
					color: #555;
	    	}
	    	h2, h3 {
	    		margin-bottom: 1em;
	    	}
	    	p {
	    		margin-bottom: 1em;
	    	}

	    	pre {
	    		margin: 1em 1em 1.5em 1em;
	    		color: black;
	    	}

	    	div.write-to {
	    		margin: 1em;
	    		border: 1px solid #999;
	    	}
	    	div.write-to p {
	    		padding: .5em;
	    		margin: 0;
	    	}
	    	div.write-to .filename {
	    		background-color: #EEE;
	    		padding: .5em;
	    		font-weight: bold;
	    	}
	    	div.write-to pre {
	    		padding: .5em;
	    		margin: 0;
	    	}

	    	pre.shell > div:before {
	    		content: "$ ";
	    		color: #666;
	    	}
        </style>
    </head>
    <body>
    <div class="container">
      <div class="row">
        <div class="col-xs-12">
        <h1>Build Your Own Mail Server From Scratch</h1>
        <p>Here&rsquo;s how you can build your own mail server from scratch. This document is generated automatically from our setup script.</p>
        <hr>
 """)

	parser = Source.parser()
	for line in open("setup/start.sh"):
		try:
			fn = parser.parse_string(line).filename()
		except:
			continue
		if fn in ("setup/preflight.sh", "setup/questions.sh", "setup/firstuser.sh", "setup/management.sh"):
			continue

		import sys
		print(fn, file=sys.stderr)

		print(BashScript.parse(fn))

	print("""
        <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.10.1/jquery.min.js"></script>
        <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.2.0/js/bootstrap.min.js"></script>
    </body>
</html>
""")

class HashBang(Grammar):
	grammar = (L('#!'), REST_OF_LINE, EOL)
	def value(self):
		return ""

def strip_indent(s):
	lines = s.split("\n")
	min_indent = min(len(re.match(r"\s*", line).group(0)) for line in lines if len(line) > 0)
	lines = [line[min_indent:] for line in lines]
	return "\n".join(lines)

class Comment(Grammar):
	grammar = ONE_OR_MORE(ZERO_OR_MORE(SPACE), L('#'), REST_OF_LINE, EOL)
	def value(self):
		if self.string.replace("#", "").strip() == "":
			return "\n"
		lines = [x[2].string for x in self[0]]
		content = "\n".join(lines)
		content = strip_indent(content)
		return markdown.markdown(content, output_format="html4") + "\n\n"

FILENAME = WORD('a-z0-9-/.')

class Source(Grammar):
	grammar = ((L('.') | L('source')), L(' '), FILENAME, Comment | EOL)
	def filename(self):
		return self[2].string.strip()
	def value(self):
		return BashScript.parse(self.filename())

class CatEOF(Grammar):
	grammar = (ZERO_OR_MORE(SPACE), L('cat > '), ANY_EXCEPT(WHITESPACE), L(" <<"), OPTIONAL(SPACE), L("EOF;"), EOL, REPEAT(ANY, greedy=False), EOL, L("EOF"), EOL)
	def value(self):
		content = self[7].string
		content = re.sub(r"\\([$])", r"\1", content) # un-escape bash-escaped characters
		return "<div class='write-to'><div class='filename'>overwrite<br>" + self[2].string + "</div><pre>" + cgi.escape(content) + "</pre></div>\n"

class HideOutput(Grammar):
	grammar = (L("hide_output "), REF("BashElement"))
	def value(self):
		return self[1].value()

class SuppressedLine(Grammar):
	grammar = (OPTIONAL(SPACE), L("echo "), REST_OF_LINE, EOL)
	def value(self):
		if "|" in self.string  or ">" in self.string:
			return "<pre class='shell'><div>" + cgi.escape(self.string.strip()) + "</div></pre>\n"
		return ""

class EditConf(Grammar):
	grammar = (
		L('tools/editconf.py '),
		FILENAME,
		SPACE,
		OPTIONAL((LIST_OF(
			L("-w") | L("-s") | L("-c ';'"),
			sep=SPACE,
		), SPACE)),
		REST_OF_LINE,
		OPTIONAL(SPACE),
		EOL
		)
	def value(self):
		conffile = self[1]
		options = [""]
		mode = 1
		for c in self[4].string:
			if mode == 1 and c in (" ", "\t") and options[-1] != "":
				# new word
				options.append("")
			elif mode < 0:
				# escaped character
				options[-1] += c
				mode = -mode
			elif c == "\\":
				# escape next character
				mode = -mode
			elif mode == 1 and c == '"':
				mode = 2
			elif mode == 2 and c == '"':
				mode = 1
			else:
				options[-1] += c
		if options[-1] == "": options.pop(-1)
		return "<div class='write-to'><div class='filename'>additional settings for<br>" + self[1].string + "</div><pre>" + "\n".join(cgi.escape(s) for s in options) + "</pre></div>\n"

class CaptureOutput(Grammar):
	grammar = OPTIONAL(SPACE), WORD("A-Za-z_"), L('=$('), REST_OF_LINE, L(")"), OPTIONAL(L(';')), EOL
	def value(self):
		cmd = self[3].string
		cmd = cmd.replace("; ", "\n")
		return "<div class='write-to'><div class='filename'>$" + self[1].string + "=</div><pre>" + cgi.escape(cmd) + "</pre></div>\n"

class SedReplace(Grammar):
	grammar = OPTIONAL(SPACE), L('sed -i "s/'), OPTIONAL(L('^')), ONE_OR_MORE(WORD("-A-Za-z0-9 #=\\{};.*$_!()")), L('/'), ONE_OR_MORE(WORD("-A-Za-z0-9 #=\\{};.*$_!()")), L('/"'), SPACE, FILENAME, EOL
	def value(self):
		return "<div class='write-to'><div class='filename'>edit<br>" + self[8].string + "</div><p>replace</p><pre>" + cgi.escape(self[3].string.replace(".*", ". . .")) + "</pre><p>with</p><pre>" + cgi.escape(self[5].string.replace("\\n", "\n").replace("\\t", "\t")) + "</pre></div>\n"

def shell_line(bash):
	return "<pre class='shell'><div>" + cgi.escape(wrap_lines(bash.strip())) + "</div></pre>\n"

class AptGet(Grammar):
	grammar = (ZERO_OR_MORE(SPACE), L("apt_install "), REST_OF_LINE, EOL)
	def value(self):
		return shell_line("apt-get install -y " + re.sub(r"\s+", " ", self[2].string))
class UfwAllow(Grammar):
	grammar = (ZERO_OR_MORE(SPACE), L("ufw_allow "), REST_OF_LINE, EOL)
	def value(self):
		return shell_line("ufw allow " + self[2].string)
class RestartService(Grammar):
	grammar = (ZERO_OR_MORE(SPACE), L("restart_service "), REST_OF_LINE, EOL)
	def value(self):
		return shell_line("service " + self[2].string + " restart")

class OtherLine(Grammar):
	grammar = (REST_OF_LINE, EOL)
	def value(self):
		if self.string.strip() == "": return ""
		return "<pre class='shell'><div>" + cgi.escape(self.string.rstrip()) + "</div></pre>\n"

class BashElement(Grammar):
	grammar = Comment | Source | CatEOF | SuppressedLine | HideOutput | EditConf | CaptureOutput | SedReplace | AptGet | UfwAllow | RestartService | OtherLine
	def value(self):
		return self[0].value()

class BashScript(Grammar):
	grammar = (OPTIONAL(HashBang), REPEAT(BashElement))
	def value(self):
		return [line.value() for line in self[1]]

	@staticmethod
	def parse(fn):
		if fn in ("setup/functions.sh", "/etc/mailinabox.conf"): return ""
		parser = BashScript.parser()
		string = open(fn).read()
		string = re.sub(r"\s*\\\n\s*", " ", string)
		string = re.sub(".* #NODOC\n", "", string)
		string = re.sub("\n\s*if .*|\n\s*fi|\n\s*else|\n\s*elif .*", "", string)
		string = re.sub("hide_output ", "", string)
		result = parser.parse_string(string)
	
		v = "<div class='sourcefile'><a href=\"%s\">%s</a></div>\n" % ("https://github.com/mail-in-a-box/mailinabox/tree/master/" + fn, fn)
		v += "".join(result.value())

		v = v.replace("</pre>\n<pre class='shell'>", "")
		v = re.sub("<pre>([\w\W]*?)</pre>", lambda m : "<pre>" + strip_indent(m.group(1)) + "</pre>", v)

		v = re.sub(r"\$?PRIMARY_HOSTNAME", "<b>box.yourdomain.com</b>", v)
		v = re.sub(r"\$?STORAGE_ROOT", "<code><b>/path/to/user-data</b></code>", v)
		v = v.replace("`pwd`",  "<code><b>/path/to/mailinabox</b></code>")

		return v

def wrap_lines(text, cols=60):
	ret = ""
	words = re.split("(\s+)", text)
	linelen = 0
	for w in words:
		if linelen + len(w) > cols-1:
			ret += " \\\n"
			ret += "   "
			linelen = 0
		if linelen == 0 and w.strip() == "": continue
		ret += w
		linelen += len(w)
	return ret

if __name__ == '__main__':
	generate_documentation()
