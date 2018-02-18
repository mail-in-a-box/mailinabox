#!/usr/bin/python3
#
# Generate documentation for how this machine works by
# parsing our bash scripts!

import cgi
import re
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
                margin-top: .25em;
                margin-bottom: .75em;
            }
            p {
                margin-bottom: 1em;
            }
                .intro p {
                    margin: 1.5em 0;
                }
            li {
                margin-bottom: .33em;
            }

            .sourcefile {
                padding-top: 1.5em;
                padding-bottom: 1em;
                font-size: 90%;
                text-align: right;
            }
                .sourcefile a {
                    color: red;
                }

            .instructions .row.contd {
                border-top: 1px solid #E0E0E0;
            }

            .prose {
                padding-top: 1em;
                padding-bottom: 1em;
            }
            .terminal {
                background-color: #EEE;
                padding-top: 1em;
                padding-bottom: 1em;
            }

            ul {
                padding-left: 1.25em;
            }

            pre {
                color: black;
                border: 0;
                background: none;
                font-size: 100%;
            }

            div.write-to {
                margin: 0 0 1em .5em;
            }
            div.write-to p {
                padding: .5em;
                margin: 0;
            }
            div.write-to .filename {
                padding: .25em .5em;
                background-color: #666;
                color: white;
                font-family: monospace;
                font-weight: bold;
            }
            div.write-to .filename span {
                font-family: sans-serif;
                font-weight: normal;
            }
            div.write-to pre {
                margin: 0;
                padding: .5em;
                border: 1px solid #999;
                border-radius: 0;
                font-size: 90%;
            }

            pre.shell > div:before {
                content: "$ ";
                color: #666;
            }
        </style>
    </head>
    <body>
    <div class="container">
      <div class="row intro">
        <div class="col-xs-12">
        <h1>Build Your Own Mail Server From Scratch</h1>
        <p>Here&rsquo;s how you can build your own mail server from scratch.</p>
        <p>This document is generated automatically from <a href="https://mailinabox.email">Mail-in-a-Box</a>&rsquo;s setup script <a href="https://github.com/mail-in-a-box/mailinabox">source code</a>.</p>
        <hr>
      </div>
    </div>
    <div class="container instructions">
 """)

    parser = Source.parser()
    for line in open("setup/start.sh"):
        try:
            fn = parser.parse_string(line).filename()
        except:
            continue
        if fn in ("setup/start.sh", "setup/preflight.sh", "setup/questions.sh",
                  "setup/firstuser.sh", "setup/management.sh"):
            continue

        import sys
        print(fn, file=sys.stderr)

        print(BashScript.parse(fn))

    print("""
        <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.10.1/jquery.min.js"></script>
        <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.2.0/js/bootstrap.min.js"></script>
        <script>
        $(function() {
            $('.terminal').each(function() {
              $(this).outerHeight( $(this).parent().innerHeight() );
            });
        })
        </script>
    </body>
</html>
""")


class HashBang(Grammar):
    grammar = (L('#!'), REST_OF_LINE, EOL)

    def value(self):
        return ""


def strip_indent(s):
    s = s.replace("\t", "    ")
    lines = s.split("\n")
    try:
        min_indent = min(len(re.match(r"\s*", line).group(0)) for line in lines if len(line) > 0)
    except ValueError:
        # No non-empty lines.
        min_indent = 0
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
    grammar = (ZERO_OR_MORE(SPACE), L('cat '), L('>') | L('>>'), L(' '), ANY_EXCEPT(WHITESPACE),
               L(" <<"), OPTIONAL(SPACE), L("EOF"), EOL, REPEAT(ANY, greedy=False), EOL, L("EOF"), EOL)

    def value(self):
        content = self[9].string
        content = re.sub(r"\\([$])", r"\1", content)  # un-escape bash-escaped characters
        return "<div class='write-to'><div class='filename'>%s <span>(%s)</span></div><pre>%s</pre></div>\n" \
            % (self[4].string,
               "overwrite" if ">>" not in self[2].string else "append to",
               cgi.escape(content))


class HideOutput(Grammar):
    grammar = (L("hide_output "), REF("BashElement"))

    def value(self):
        return self[1].value()


class EchoLine(Grammar):
    grammar = (OPTIONAL(SPACE), L("echo "), REST_OF_LINE, EOL)

    def value(self):
        if "|" in self.string or ">" in self.string:
            return "<pre class='shell'><div>" + recode_bash(self.string.strip()) + "</div></pre>\n"
        return ""


class EditConf(Grammar):
    grammar = (
        L('tools/editconf.py '),
        FILENAME,
        SPACE,
        OPTIONAL((LIST_OF(
            L("-w") | L("-s") | L("-c ;"),
            sep=SPACE,
        ), SPACE)),
        REST_OF_LINE,
        OPTIONAL(SPACE),
        EOL
        )

    def value(self):
        conffile = self[1]
        options = []
        eq = "="
        if self[3] and "-s" in self[3].string:
            eq = " "
        for opt in re.split("\s+", self[4].string):
            k, v = opt.split("=", 1)
            v = re.sub(r"\n+", "", fixup_tokens(v))  # not sure why newlines are getting doubled
            options.append("%s%s%s" % (k, eq, v))
        return "<div class='write-to'><div class='filename'>" + self[1].string +
        " <span>(change settings)</span></div><pre>" +
        "\n".join(cgi.escape(s) for s in options) + "</pre></div>\n"


class CaptureOutput(Grammar):
    grammar = OPTIONAL(SPACE), WORD("A-Za-z_"), L('=$('), REST_OF_LINE, L(")"), OPTIONAL(L(';')), EOL

    def value(self):
        cmd = self[3].string
        cmd = cmd.replace("; ", "\n")
        return "<div class='write-to'><div class='filename'>$" +
        self[1].string + "=</div><pre>" + cgi.escape(cmd) + "</pre></div>\n"


class SedReplace(Grammar):
    grammar = OPTIONAL(SPACE), L('sed -i "s/'), OPTIONAL(L('^')), \
        ONE_OR_MORE(WORD("-A-Za-z0-9 #=\\{};.*$_!()")), L('/'), \
        ONE_OR_MORE(WORD("-A-Za-z0-9 #=\\{};.*$_!()")), L('/"'), SPACE, FILENAME, EOL

    def value(self):
        return "<div class='write-to'><div class='filename'>edit<br>" + self[8].string +
        "</div><p>replace</p><pre>" + cgi.escape(self[3].string.replace(".*", ". . .")) +
        "</pre><p>with</p><pre>" +
        cgi.escape(self[5].string.replace("\\n", "\n").replace("\\t", "\t")) + "</pre></div>\n"


class EchoPipe(Grammar):
    grammar = OPTIONAL(SPACE), L("echo "), REST_OF_LINE, L(' | '), REST_OF_LINE, EOL

    def value(self):
        text = " ".join("\"%s\"" % s for s in self[2].string.split(" "))
        return "<pre class='shell'><div>echo " + recode_bash(text) +
        " \<br> | " + recode_bash(self[4].string) + "</div></pre>\n"


def shell_line(bash):
    return "<pre class='shell'><div>" + recode_bash(bash.strip()) + "</div></pre>\n"


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
        if self.string.strip() == "":
            return ""
        if "source setup/functions.sh" in self.string:
            return ""
        if "source /etc/mailinabox.conf" in self.string:
            return ""
        return "<pre class='shell'><div>" + recode_bash(self.string.strip()) + "</div></pre>\n"


class BashElement(Grammar):
    grammar = Comment | CatEOF | EchoPipe | EchoLine | HideOutput | EditConf | \
       SedReplace | AptGet | UfwAllow | RestartService | OtherLine

    def value(self):
        return self[0].value()


# Make some special characters to private use Unicode code points.
bash_special_characters1 = {
    "\n": "\uE000",
    " ": "\uE001",
}
bash_special_characters2 = {
    "$": "\uE010",
}
bash_escapes = {
    "n": "\uE020",
    "t": "\uE021",
}


def quasitokenize(bashscript):
    # Make a parse of bash easier by making the tokenization easy.
    newscript = ""
    quote_mode = None
    escape_next = False
    line_comment = False
    subshell = 0
    for c in bashscript:
        if line_comment:
            # We're in a comment until the end of the line.
            newscript += c
            if c == '\n':
                line_comment = False
        elif escape_next:
            # Previous character was a \. Normally the next character
            # comes through literally, but escaped newlines are line
            # continuations and some escapes are for special characters
            # which we'll recode and then turn back into escapes later.
            if c == "\n":
                c = " "
            elif c in bash_escapes:
                c = bash_escapes[c]
            newscript += c
            escape_next = False
        elif c == "\\":
            # Escaping next character.
            escape_next = True
        elif quote_mode is None and c in ('"', "'"):
            # Starting a quoted word.
            quote_mode = c
        elif c == quote_mode:
            # Ending a quoted word.
            quote_mode = None
        elif quote_mode is not None and quote_mode != "EOF" and c in bash_special_characters1:
            # Replace special tokens within quoted words so that they
            # don't interfere with tokenization later.
            newscript += bash_special_characters1[c]
        elif quote_mode is None and c == '#':
            # Start of a line comment.
            newscript += c
            line_comment = True
        elif quote_mode is None and c == ';' and subshell == 0:
            # End of a statement.
            newscript += "\n"
        elif quote_mode is None and c == '(':
            # Start of a subshell.
            newscript += c
            subshell += 1
        elif quote_mode is None and c == ')':
            # End of a subshell.
            newscript += c
            subshell -= 1
        elif quote_mode is None and c == '\t':
            # Make these just spaces.
            if newscript[-1] != " ":
                newscript += " "
        elif quote_mode is None and c == ' ':
            # Collapse consecutive spaces.
            if newscript[-1] != " ":
                newscript += " "
        elif c in bash_special_characters2:
            newscript += bash_special_characters2[c]
        else:
            # All other characters.
            newscript += c

        # "<< EOF" escaping.
        if quote_mode is None and re.search("<<\s*EOF\n$", newscript):
            quote_mode = "EOF"
        elif quote_mode == "EOF" and re.search("\nEOF\n$", newscript):
            quote_mode = None

    return newscript


def recode_bash(s):
    def requote(tok):
        tok = tok.replace("\\", "\\\\")
        for c in bash_special_characters2:
            tok = tok.replace(c, "\\" + c)
        tok = fixup_tokens(tok)
        if " " in tok or '"' in tok:
            tok = tok.replace("\"", "\\\"")
            tok = '"' + tok + '"'
        else:
            tok = tok.replace("'", "\\'")
        return tok
    return cgi.escape(" ".join(requote(tok) for tok in s.split(" ")))


def fixup_tokens(s):
    for c, enc in bash_special_characters1.items():
        s = s.replace(enc, c)
    for c, enc in bash_special_characters2.items():
        s = s.replace(enc, c)
    for esc, c in bash_escapes.items():
        s = s.replace(c, "\\" + esc)
    return s


class BashScript(Grammar):
    grammar = (OPTIONAL(HashBang), REPEAT(BashElement))

    def value(self):
        return [line.value() for line in self[1]]

    @staticmethod
    def parse(fn):
        if fn in ("setup/functions.sh", "/etc/mailinabox.conf"):
            return ""
        string = open(fn).read()

        # tokenize
        string = re.sub(".* #NODOC\n", "", string)
        string = re.sub("\n\s*if .*then.*|\n\s*fi|\n\s*else|\n\s*elif .*", "", string)
        string = quasitokenize(string)
        string = re.sub("hide_output ", "", string)

        parser = BashScript.parser()
        result = parser.parse_string(string)

        v = ("<div class='row'><div class='col-xs-12 sourcefile'>view the bash source for \
              the following section at <a href=\"%s\">%s</a></div></div>\n") \
            % ("https://github.com/mail-in-a-box/mailinabox/tree/master/" + fn, fn)

        mode = 0
        for item in result.value():
            if item.strip() == "":
                pass
            elif item.startswith("<p") and not item.startswith("<pre"):
                clz = ""
                if mode == 2:
                    v += "</div>\n"  # col
                    v += "</div>\n"  # row
                    mode = 0
                    clz = "contd"
                if mode == 0:
                    v += "<div class='row %s'>\n" % clz
                    v += "<div class='col-md-6 prose'>\n"
                v += item
                mode = 1
            elif item.startswith("<h"):
                if mode != 0:
                    v += "</div>\n"  # col
                    v += "</div>\n"  # row
                v += "<div class='row'>\n"
                v += "<div class='col-md-6 header'>\n"
                v += item
                v += "</div>\n"  # col
                v += "<div class='col-md-6 terminal'> </div>\n"
                v += "</div>\n"  # row
                mode = 0
            else:
                if mode == 0:
                    v += "<div class='row'>\n"
                    v += "<div class='col-md-offset-6 col-md-6 terminal'>\n"
                elif mode == 1:
                    v += "</div>\n"
                    v += "<div class='col-md-6 terminal'>\n"
                mode = 2
                v += item

        v += "</div>\n"  # col
        v += "</div>\n"  # row

        v = fixup_tokens(v)

        v = v.replace("</pre>\n<pre class='shell'>", "")
        v = re.sub("<pre>([\w\W]*?)</pre>", lambda m: "<pre>" + strip_indent(m.group(1)) + "</pre>", v)

        v = re.sub(r"(\$?)PRIMARY_HOSTNAME", r"<b>box.yourdomain.com</b>", v)
        v = re.sub(r"\$STORAGE_ROOT", r"<b>$STORE</b>", v)
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
        if linelen == 0 and w.strip() == "":
            continue
        ret += w
        linelen += len(w)
    return ret


if __name__ == '__main__':
    generate_documentation()
