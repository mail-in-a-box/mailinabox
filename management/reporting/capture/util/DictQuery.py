#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####



class DictQuery(object):

    @staticmethod
    def find(data_list, q_list, return_first_exact=False, reverse=False):
        '''find items in list `data_list` using the query specified in
           `q_list` (a list of dicts).

            side-effects:
               q_list is modified ('_val' is added)

        '''
        if data_list is None:
            if return_first_exact:
                return None
            else:
                return []

        if type(q_list) is not list:
            q_list = [ q_list ]

        # set _val to value.lower() if ignorecase is True
        for q in q_list:
            if q=='*': continue
            ignorecase = q.get('ignorecase', False)
            match_val = q['value']
            if ignorecase and match_val is not None:
                match_val = match_val.lower()
            q['_val'] = match_val

        # find all matches
        matches = []
        direction = -1 if reverse else 1
        idx = len(data_list)-1 if reverse else 0
        while (reverse and idx>=0) or (not reverse and idx<len(data_list)):
            item = data_list[idx]
            if 'rank' in item and 'item' in item:
                # for re-querying... 
                item=item['item']
            count_mismatch = 0
            autoset_list = []
            optional_list = []

            for q in q_list:
                if q=='*': continue
                cmp_val = item.get(q['key'])
                if cmp_val is not None and q.get('ignorecase'):
                    cmp_val = cmp_val.lower()

                op = q.get('op', '=')
                mismatch = False
                if op == '=':
                    mismatch = q['_val'] != cmp_val
                elif op == '!=':
                    mismatch = q['_val'] == cmp_val
                else:
                    raise TypeError('No such op:  ' + op)
                    
                if mismatch:
                    count_mismatch += 1                        
                    if cmp_val is None:
                        if q.get('autoset'):
                            autoset_list.append(q)
                        elif q.get('optional'):
                            optional_list.append(q)
                    if return_first_exact:
                        break

            if return_first_exact:
                if count_mismatch == 0:
                    return item
            else:            
                optional_count = len(autoset_list) + len(optional_list)
                if count_mismatch - optional_count == 0:
                    rank = '{0:05d}.{1:08d}'.format(
                        optional_count,
                        len(data_list) - idx if reverse else idx
                    )
                    matches.append({
                        'exact': ( optional_count == 0 ),
                        'rank': rank,
                        'autoset_list': autoset_list,
                        'optional_list': optional_list,
                        'item': item
                    })

            idx += direction

        if not return_first_exact:
            # return the list sorted so the items with the fewest
            # number of required autoset/optional's appear first
            matches.sort(key=lambda x: x['rank'])
            return matches


    @staticmethod
    def autoset(match, incl_optional=False):
        item = match['item']
        for q in match['autoset_list']:
            assert item.get(q['key']) is None
            item[q['key']] = q['value']
        if incl_optional:
            for q in match['optional_list']:
                item[q['key']] = q['value']



