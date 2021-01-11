import datetime
import bisect

class Timeseries(object):
    def __init__(self, desc, start_date, end_date, binsize):
        # start_date: 'YYYY-MM-DD' or 'YYYY-MM-DD HH:MM:SS'
        #      start: 'YYYY-MM-DD HH:MM:SS'
        self.start = self.full_datetime_str(start_date, False)
        
        #   end_date: 'YYYY-MM-DD' or 'YYYY-MM-DD HH:MM:SS'
        #        end: 'YYYY-MM-DD HH:MM:SS'
        self.end = self.full_datetime_str(end_date, True)

        # binsize: integer in minutes
        self.binsize = binsize

        # timefmt is a format string for sqlite strftime() that puts a
        # sqlite datetime into a "bin" date
        self.timefmt='%Y-%m-%d'

        # parsefmt is a date parser string to be used to re-interpret
        # "bin" grouping dates (data.dates) to native dates
        parsefmt='%Y-%m-%d'

        b = self.binsizeWithUnit()

        if b['unit'] == 'hour':
            self.timefmt+=' %H:00:00'
            parsefmt+=' %H:%M:%S'
        elif b['unit'] == 'minute':
            self.timefmt+=' %H:%M:00'
            parsefmt+=' %H:%M:%S'

        self.dates = []   # dates must be "bin" date strings
        self.series = []
        
        self.data = {
            'range': [ self.start, self.end ],
            'range_parse_format': '%Y-%m-%d %H:%M:%S',
            'binsize': self.binsize,
            'date_parse_format': parsefmt,
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
        if i == len(self.dates):
            self.dates.append(date_str)
            return i
        if self.dates[i] == date_str:
            return i
        self.dates.insert(i, date_str)
        return i
        
    def add_series(self, id, name):
        s = {
            'id': id,
            'name': name,
            'values': []
        }
        self.series.append(s)
        return s

    
    def asDict(self):
        return self.data
    
