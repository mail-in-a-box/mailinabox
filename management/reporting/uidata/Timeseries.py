#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

import datetime
import bisect

class Timeseries(object):
    def __init__(self, desc, start_date, end_date, binsize):
        # start_date: 'YYYY-MM-DD' or 'YYYY-MM-DD HH:MM:SS'
        #      start: 'YYYY-MM-DD HH:MM:SS'
        self.start = self.full_datetime_str(start_date, False)
        self.start_unixepoch = self.unix_time(self.start)
        
        #   end_date: 'YYYY-MM-DD' or 'YYYY-MM-DD HH:MM:SS'
        #        end: 'YYYY-MM-DD HH:MM:SS'
        self.end = self.full_datetime_str(end_date, True)

        # binsize: integer in minutes
        self.binsize = binsize

        # timefmt is a format string for sqlite strftime() that puts a
        # sqlite datetime into a "bin" date
        self.timefmt = '%Y-%m-%d %H:%M:%S'

        # parsefmt is a date parser string to be used to re-interpret
        # "bin" grouping dates (data.dates) to native dates. server
        # always returns utc dates
        self.parsefmt = '%Y-%m-%d %H:%M:%S'

        self.dates = []   # dates must be "bin" date strings
        self.series = []
        
        self.data = {
            'range': [ self.start, self.end ],
            'range_parse_format': '%Y-%m-%d %H:%M:%S',
            'binsize': self.binsize,
            'date_parse_format': self.parsefmt,
            'y': desc,
            'dates': self.dates,
            'series': self.series
        }

    def full_datetime_str(self, date_str, next_day):
        if ':' in date_str:
            return date_str
        elif not next_day:
            return date_str + " 00:00:00"
        else:
            d = datetime.datetime.strptime(date_str, '%Y-%m-%d')
            d = d + datetime.timedelta(days=1)
            return d.strftime('%Y-%m-%d 00:00:00')

    def unix_time(self, full_datetime_str):
        d = datetime.datetime.strptime(
            full_datetime_str + ' UTC',
            '%Y-%m-%d %H:%M:%S %Z'
        )
        return int(d.timestamp())
        

    def binsizeWithUnit(self):
        # normalize binsize (which is a time span in minutes)
        days = int(self.binsize / (24 * 60))
        hours = int((self.binsize - days*24*60) / 60 )
        mins = self.binsize - days*24*60 - hours*60
        if days == 0 and hours == 0:
            return {
                'unit': 'minute',
                'value': mins
            }
        
        if days == 0:
            return {
                'unit': 'hour',
                'value': hours
            }
        
        return {
            'unit': 'day',
            'value': days
        }

    
    def append_date(self, date_str):
        '''date_str should be a "bin" date - that is a date formatted with
        self.timefmt. 

        1. it should be greater than the previous bin so that the date
        list remains sorted

        2. d3js does not require that all dates be added for a
        timespan if there is no data for the bin

        '''
        self.dates.append(date_str)

    def insert_date(self, date_str):
        '''adds bin date if it does not exist and returns the new index.  if
        the date already exists, returns the existing index.

        '''
        i = bisect.bisect_right(self.dates, date_str)
        if len(self.dates)>0 and self.dates[i-1] == date_str:
            return i-1
        elif i == len(self.dates):
            self.dates.append(date_str)
        else:
            self.dates.insert(i, date_str)

        ''' add zero values to all series for the new date '''
        for series in self.series:
            series['values'].insert(i, 0)
            
        return i
        
    def add_series(self, id, name):
        s = {
            'id': id,
            'name': name,
            'values': []
        }
        self.series.append(s)
        for date in self.dates:
            s['values'].append(0)
        return s

    
    def asDict(self):
        return self.data
    
