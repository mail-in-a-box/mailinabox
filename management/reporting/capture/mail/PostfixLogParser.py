
class PostfixLogParser(object):

    @staticmethod
    def split_host(str):
        ''' split string in form HOST[IP] and return HOST and IP '''
        ip_start = str.find('[')
        ip_end = -1
        if ip_start>=0:
            ip_end = str.find(']', ip_start)
            if ip_start<0 or ip_end<0:
                return str, str
            return str[0:ip_start], str[ip_start+1:ip_end]

    @staticmethod
    def strip_brackets(str, bracket_l='<', bracket_r='>'):
        # strip enclosing '<>'
        if len(str)>=2 and str[0]==bracket_l and str[-1]==bracket_r:
            return str[1:-1]
        return str


    class SplitList(object):
        ''' split a postfix name=value list. For example:

        "delay=4.7, to=<alice@post.com>, status=sent (250 2.0.0 <user@domain.tld> YB5nM1eS01+lSgAAlWWVsw Saved)"

        returns: {
           "delay": {
                "name": "delay",
                "value": "4.7"
           },
           "to": {
                "name": "to",
                "value": "alice@post.com"
           },
           "status": {
                "name": "status",
                "value": "sent",
                "comment": "250 2.0.0 <user@domain.tld> YB5nM1eS01+lSgAAlWWVsw Saved"
           }
        }

        '''
        def __init__(self, str, delim=',', strip_brackets=True):
            self.str = str
            self.delim = delim
            self.strip_brackets = True
            self.pos = 0

        def asDict(self):
            d = {}
            for pair in self:
                d[pair['name']] = pair
            return d

        def __iter__(self):
            self.pos = 0
            return self

        def __next__(self):
            if self.pos >= len(self.str):
                raise StopIteration

            # name
            eq = self.str.find('=', self.pos)
            if eq<0:
                self.pos = len(self.str)
                raise StopIteration

            name = self.str[self.pos:eq].strip()

            # value and comment
            self.pos = eq+1
            value = []
            comment = []

            while self.pos < len(self.str):
                c = self.str[self.pos]
                self.pos += 1

                if c=='<':
                    idx = self.str.find('>', self.pos)
                    if idx>=0:
                        value.append(self.str[self.pos-1:idx+1])
                        self.pos = idx+1
                        continue

                if c=='(':
                    # parens may be nested...
                    open_count = 1
                    begin = self.pos
                    while self.pos < len(self.str) and open_count>0:
                        c = self.str[self.pos]
                        self.pos += 1
                        if c=='(':
                            open_count += 1
                        elif c==')':
                            open_count -= 1
                    if open_count == 0:
                        comment.append(self.str[begin:self.pos-1])
                    else:
                        comment.append(self.str[begin:len(self.str)])
                    continue

                if c==self.delim:
                    break

                begin = self.pos-1
                while self.pos < len(self.str):
                    lookahead = self.str[self.pos]
                    if lookahead in [self.delim,'<','(']:
                        break
                    self.pos += 1

                value.append(self.str[begin:self.pos])

            if self.strip_brackets and len(value)==1:
                value[0] = PostfixLogParser.strip_brackets(value[0])

            return {
                'name': name,
                'value': ''.join(value),
                'comment': None if len(comment)==0 else '; '.join(comment)
            }
