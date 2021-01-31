
class ChartPrefs {
    static get colors() {
        // see: https://github.com/d3/d3-scale-chromatic
        return d3.schemeSet2;
    }

    static get line_colors() {
        // see: https://github.com/d3/d3-scale-chromatic
        return d3.schemeCategory10;
    }

    static get default_width() {
        return 600;
    }

    static get default_height() {
        return 400;
    }

    static get axis_font_size() {
        return 12;
    }

    static get default_font_size() {
        return 10;
    }

    static get label_font_size() {
        return 12;
    }

    static get default_font_family() {
        return "sans-serif";
    }

    static get locales() {
        return "en";
    }
};


class DateFormatter {
    /*
     * date and time
     */
    static dt_long(d, options) {
        let opt = {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric'
        };
        Object.assign(opt, options);
        return d.toLocaleString(ChartPrefs.locales, opt);
    }
    static dt_short(d, options) {
        return d.toLocaleString(ChartPrefs.locales, options);
    }

    /*
     * date
     */
    static d_long(d, options) {
        let opt = {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric'
        };
        Object.assign(opt, options);
        return d.toLocaleDateString(ChartPrefs.locales, opt);
    }
    static d_short(d, options) {
        return d.toLocaleDateString(ChartPrefs.locales, options);
    }

    /*
     * time
     */
    static t_long(d, options) {
        return d.toLocaleTimeString(ChartPrefs.locales, options);
    }
    static t_short(d, options) {
        return d.toLocaleTimeString(ChartPrefs.locales, options);
    }
    static t_span(d, unit) {
        // `d` is milliseconds
        // `unit` is desired max precision output unit (eg 's')
        unit = unit || 's';
        const cvt = [{
            ms: (24 * 60 * 60 * 1000),
            ushort: 'd',
            ulong: 'day'
        }, {
            ms: (60 * 60 * 1000),
            ushort: 'h',
            ulong: 'hour'
        }, {
            ms: (60 * 1000),
            ushort: 'm',
            ulong: 'minute'
        }, {
            ms: 1000,
            ushort: 's',
            ulong: 'second'
        }, {
            ms: 1,
            ushort: 'ms',
            ulong: 'milliseconds'
        }];

        var first = false;
        var remainder = d;
        var out = [];
        var done = false;
        cvt.forEach( c => {
            if (done) return;
            var amt = Math.floor( remainder / c.ms );
            remainder = remainder % c.ms;
            if (first || amt > 0) {
                first = true;
                out.push(amt + c.ushort);
            }
            if (unit == c.ushort || unit == c.ulong) {
                done = true;
            }
        });        
        return out.join(' ');
    }

    /*
     * universal "YYYY-MM-DD HH:MM:SS" formats
     */
    static ymd(d) {
        const ye = d.getFullYear();
        const mo = '0'+(d.getMonth() + 1);
        const da = '0'+d.getDate();
        return `${ye}-${mo.substr(mo.length-2)}-${da.substr(da.length-2)}`;
    }

    static ymd_utc(d) {
        const ye = d.getUTCFullYear();
        const mo = '0'+(d.getUTCMonth() + 1);
        const da = '0'+d.getUTCDate();
        return `${ye}-${mo.substr(mo.length-2)}-${da.substr(da.length-2)}`;
    }

    static ymdhms(d) {
        const ho = '0'+d.getHours();
        const mi = '0'+d.getMinutes();
        const se = '0'+d.getSeconds();
        return `${DateFormatter.ymd(d)} ${ho.substr(ho.length-2)}:${mi.substr(mi.length-2)}:${se.substr(se.length-2)}`;
    }

    static ymdhms_utc(d) {
        const ho = '0'+d.getUTCHours();
        const mi = '0'+d.getUTCMinutes();
        const se = '0'+d.getUTCSeconds();
        return `${DateFormatter.ymd_utc(d)} ${ho.substr(ho.length-2)}:${mi.substr(mi.length-2)}:${se.substr(se.length-2)}`;
    }
};


class DateRange {
    /*
     * ranges
     */
    static ytd() {
        var s = new Date();
        s.setMonth(0);
        s.setDate(1);
        s.setHours(0);
        s.setMinutes(0);
        s.setSeconds(0);
        s.setMilliseconds(0);
        return [ s, new Date() ];
    }
    static ytd_as_ymd() {
        return DateRange.ytd().map(d => DateFormatter.ymd(d));
    }

    static mtd() {
        var s = new Date();
        s.setDate(1);
        s.setHours(0);
        s.setMinutes(0);
        s.setSeconds(0);
        s.setMilliseconds(0);
        return [ s, new Date() ];
    }
    static mtd_as_ymd() {
        return DateRange.mtd().map(d => DateFormatter.ymd(d));
    }

    static wtd() {
        var s = new Date();
        var offset = s.getDay() * (24 * 60 * 60 * 1000);
        s.setTime(s.getTime() - offset);
        s.setHours(0);
        s.setMinutes(0);
        s.setSeconds(0);
        s.setMilliseconds(0);
        return [ s, new Date() ];
    }
    static wtd_as_ymd() {
        return DateRange.wtd().map(d => DateFormatter.ymd(d));
    }

    static rangeFromType(type) {
        if (type == 'wtd')
            return DateRange.wtd();
        else if (type == 'mtd')
            return DateRange.mtd();
        else if (type == 'ytd')
            return DateRange.ytd();
        return null;
    }
};


class NumberFormatter {
    static format(v) {
        return isNaN(v) || v===null ? "N/A" : v.toLocaleString(ChartPrefs.locales);
    }

    static decimalFormat(v, places, style) {
        if (isNaN(v) || v===null) return "N/A";
        if (places === undefined || isNaN(places)) places = 1;
        if (style === undefined || typeof style != 'string') style = 'decimal';
        var options = {
            style: style,
            minimumFractionDigits: places
        };
        v = v.toLocaleString(ChartPrefs.locales, options);
        return v;        
    }

    static percentFormat(v, places) {
        if (places === undefined || isNaN(places)) places = 0;
        return NumberFormatter.decimalFormat(v, places, 'percent');
    }

    static humanFormat(v, places) {
        if (isNaN(v) || v===null) return "N/A";
        if (places === undefined || isNaN(places)) places = 1;
        const options = {
            style: 'unit',
            minimumFractionDigits: places,
            unit: 'byte'
        };
        var xunit = '';
        const f = Math.pow(10, places);
        if (v >= NumberFormatter.tb) {
            v = Math.round(v / NumberFormatter.tb * f) / f;
            options.unit='terabyte';
            xunit = 'T';
        }
        else if (v >= NumberFormatter.gb) {
            v = Math.round(v / NumberFormatter.gb * f) / f;
            options.unit='gigabyte';
            xunit = 'G';
        }
        else if (v >= NumberFormatter.mb) {
            v = Math.round(v / NumberFormatter.mb * f) / f;
            options.unit='megabyte';
            xunit = 'M';
        }
        else if (v >= NumberFormatter.kb) {
            v = Math.round(v / NumberFormatter.kb * f) / f;
            options.unit='kilobyte';
            xunit = 'K';
        }
        else {
            options.minimumFractionDigits = 0;
            places = 0;
        }
        try {
            return v.toLocaleString(ChartPrefs.locales, options);
        } catch(e) {
            if (e instanceof RangeError) {
                // probably "invalid unit"
                return NumberFormatter.decimalFormat(v, places) + xunit;
            }
        }
    }
};

// define static constants in NumberFormatter
['kb','mb','gb','tb'].forEach((unit,idx) => {
    Object.defineProperty(NumberFormatter, unit, {
        value: Math.pow(1024, idx+1),
        writable: false,
        enumerable: false,
        configurable: false
    });
});


class BvTable {
    constructor(data, opt) {
        opt = opt || {};
        Object.assign(this, data);
        if (!this.items || !this.fields || !this.field_types) {
            throw new AssertionError();
        }

        BvTable.arraysToObjects(this.items, this.fields);
        BvTable.setFieldDefinitions(this.fields, this.field_types);

        if (opt._showDetails) {
            // _showDetails must be set to make it reactive
            this.items.forEach(item => {
                item._showDetails = false;
            })
        }
    }

    field_index_of(key) {
        for (var i=0; i<this.fields.length; i++) {
            if (this.fields[i].key == key) return i;
        }
        return -1;
    }

    get_field(key, only_showing) {
        var i = this.field_index_of(key);
        if (i>=0) return this.fields[i];
        return this.x_fields && !only_showing ? this.x_fields[key] : null;
    }

    combine_fields(names, name2, formatter) {
        // combine field(s) `names` into `name2`, then remove
        // `names`. use `formatter` as the formatter function
        // for the new combined field.
        //
        // if name2 is not given, just remove all `names` fields
        //
        // removed fields are placed into this.x_fields array
        if (typeof names == 'string') names = [ names ]
        var idx2 = name2 ? this.field_index_of(name2) : -1;
        if (! this.x_fields) this.x_fields = {};
                
        names.forEach(name1 => {
            var idx1 = this.field_index_of(name1);
            if (idx1 < 0) return;
            this.x_fields[name1] = this.fields[idx1];
            this.fields.splice(idx1, 1);
            if (idx2>idx1) --idx2;
        });
        
        if (idx2 < 0) return null;
        
        this.fields[idx2].formatter = formatter;
        return this.fields[idx2];
    }

    
    static arraysToObjects(items, fields) {
        /*
         * convert array-of-arrays `items` to an array of objects
         * suitable for a <b-table> items (rows of the table).
         *
         * `items` is modified in-place
         *
         * `fields` is an array of strings, which will become the keys
         * of each new object. the length of each array in `items`
         * must match the length of `fields` and the indexes must
         * correspond.
         *
         * the primary purpose is to allow the data provider (server)
         * to send something like:
         *
         *   { "items": [ 
         *        [ "alice", 10.6, 200, "top-10" ],
         *         .... 
         *     ], 
         *     "fields": [ "name", "x", "y", "label" ] 
         *   }
         *
         * instead of:
         *
         *   { "items": [ 
         *        { "name":"a", "x":10.6, "y":200, "label":"top-10" },
         *        ... 
         *     ],
         *     "fields": [ "name", "x", "y", "label" ]
         *   }
         *
         * which requires much more bandwidth
         * 
         */
        if (items.length > 0 && !Array.isArray(items[0]))
        {
            // already converted
            return;
        }
        for (var i=0; i<items.length; i++) {
            var o = {};
            fields.forEach((field, idx) => {
                o[field] = items[i][idx];
            });
            items[i] = o;
        }
    }
    
    static setFieldDefinitions(fields, types) {
        /* 
         * change elements of array `fields` to bootstrap-vue table
         * field (column) definitions
         *
         * `fields` is an array of field names or existing field
         * definitions to update. `types` is a correponding array
         * having the type of each field which will cause one or more
         * of the following properties to be set on each field:
         * 'tdClass', 'thClass', 'label', and 'formatter'
         */
        for (var i=0; i<fields.length && i<types.length; i++) {
            var field = fields[i];
            fields[i] = new BvTableField(field, types[i]);
        }
    }
    
};


class BvTableField {
    constructor(field, field_type) {
        // this:
        //    key    - required
        //    label
        //    tdClass
        //    thClass
        //    formatter
        // .. etc (see bootstrap-vue Table component docs)

        if (typeof field == 'string') {
            this.key = field;
        }
        else {
            Object.assign(this, field);
        }

        var ft = field_type;
        var field = this;
        
        if (typeof ft == 'string') {
            ft = { type: ft };
        }

        if (! ft.subtype && ft.type.indexOf('/') >0) {
            // optional format, eg "text/email"
            var s = ft.type.split('/');
            ft.type = s[0];
            ft.subtype = s.length > 1 ? s[1] : null;
        }
        
        if (ft.label !== undefined) {
            field.label = ft.label;
        }
        
        if (ft.type == 'decimal') {
            Object.assign(ft, {
                type: 'number',
                subtype: 'decimal'
            });
        }
        
        if (ft.type == 'text')  {
            // as-is
        }
        else if (ft.type == 'number') {
            if (ft.subtype == 'plain' ||
                ft.subtype == 'decimal' && isNaN(ft.places)
               )
            {
                Object.assign(
                    field,
                    BvTableField.numberFieldDefinition()
                );
            }
        
            else if (ft.subtype == 'size') {
                Object.assign(
                    field,
                    BvTableField.sizeFieldDefinition()
                );
            }
        
            else if (ft.subtype == 'decimal') {
                Object.assign(
                    field,
                    BvTableField.decimalFieldDefinition(ft.places)
                );
            }
        
            else if (ft.subtype == 'percent') {
                Object.assign(
                    field,
                    BvTableField.percentFieldDefinition(ft.places)
                );
            }
        }
        else if (ft.type == 'datetime') {
            Object.assign(
                field,
                BvTableField.datetimeFieldDefinition(ft.showas || 'short', ft.format)
            );
        }
        else if (ft.type == 'time' && ft.subtype == 'span') {
            Object.assign(
                field,
                BvTableField.timespanFieldDefinition(ft.unit || 'ms')
            );
        }
        
    }


    static numberFieldDefinition() {
        // <b-table> field definition for a localized numeric value.
        // eg: "5,001". for additional attributes, see:
        // https://bootstrap-vue.org/docs/components/table#field-definition-reference
        return {
            formatter: NumberFormatter.format,
            tdClass: 'text-right',
            thClass: 'text-right'
        };
    }

    static sizeFieldDefinition(decimal_places) {
        // <b-table> field definition for a localized numeric value in
        // human readable format. eg: "5.1K".  `decimal_places` is
        // optional, which defaults to 1
        return {
            formatter: value =>
                NumberFormatter.humanFormat(value, decimal_places),
            tdClass: 'text-right text-nowrap',
            thClass: 'text-right'
        };
    }

    static datetimeFieldDefinition(variant, format) {
        // if the formatter is passed string (utc) dates, convert them
        // to a native Date objects using the format in `format`.  eg:
        // "%Y-%m-%d %H:%M:%S".
        //
        // `variant` can be "long" (default) or "short"
        var parser = (format ? d3.utcParse(format) : null);        
        if (variant === 'short') {
            return {
                formatter: v =>
                    DateFormatter.dt_short(parser ? parser(v) : v)
            };
        }
        else {
            return {
                formatter: v =>
                    DateFormatter.dt_long(parser ? parser(v) : v)
            };
        }
    }

    static timespanFieldDefinition(unit, output_unit) {
        var factor = 1;
        if (unit == 's') factor = 1000;
        return {
            formatter: v => DateFormatter.t_span(v * factor, output_unit)
        };
    }

    static decimalFieldDefinition(decimal_places) {
        return {
            formatter: value =>
                NumberFormatter.decimalFormat(value, decimal_places),
            tdClass: 'text-right',
            thClass: 'text-right'
        };
    }

    static percentFieldDefinition(decimal_places) {
        return {
            formatter: value =>
                NumberFormatter.percentFormat(value, decimal_places),
            tdClass: 'text-right',
            thClass: 'text-right'
        };
    }

    add_cls(cls, to_what) {
        if (Array.isArray(this[to_what])) {
            this[to_what].push(cls);
        }
        else if (this[to_what] !== undefined) {
            this[to_what] = [ this[to_what], cls ];
        }
        else {
            this[to_what] = cls;
        }
    }

    add_tdClass(cls) {
        this.add_cls(cls, 'tdClass');
    }

};


class MailBvTable extends BvTable {
    flag(key, fn) {
        var field = this.get_field(key, true);
        if (!field) return;
        field.add_tdClass(fn);
    }
    
    flag_fields(tdClass) {
        // flag on certain cell values by setting _flagged in each
        // "flagged" item during its tdClass callback function. add
        // `tdClass` to the rendered value
        
        tdClass = tdClass || 'text-danger';
        
        this.flag('accept_status', (v, key, item) => {
            if (v === 'reject') {
                item._flagged = true;
                return tdClass;
            }
        });
                
        this.flag('relay', (v, key, item) => {
            if (item.delivery_connection == 'untrusted') {
                item._flagged = true;
                return tdClass;
            }
        });

        this.flag('status', (v, key, item) => {
            if (v != 'sent') {
                item._flagged = true;
                return tdClass;
            }
        });

        this.flag('spam_result', (v, key, item) => {
            if (item.spam_result && v != 'clean') {
                item._flagged = true;
                return tdClass;
            }
        });

        this.flag('spf_result', (v, key, item) => {
            if (v == 'Fail' ||v == 'Softfail') {
                item._flagged = true;
                return tdClass;
            }
        });
        
        this.flag('dkim_result', (v, key, item) => {
            if (item.dkim_result && v != 'pass') {
                item._flagged = true;
                return tdClass;
            }
        });
        
        this.flag('dmarc_result', (v, key, item) => {
            if (v == 'fail') {
                item._flagged = true;
                return tdClass;
            }
        });

        this.flag('postgrey_result', (v, key, item) => {
            if (item.postgrey_result && v != 'pass') {
                item._flagged = true;
                return tdClass;
            }
        });

        this.flag('disposition', (v, key, item) => {
            if (item.disposition != 'ok') {
                item._flagged = true;
                return tdClass;
            }
        });

        return this;
    }

    apply_rowVariant_grouping(variant, group_fn) {
        // there is 1 row for each recipient of a message
        // - give all rows of the same message the same
        // color
        //
        // variant is a bootstrap variant like "primary"
        //
        // group_fn is a callback receiving an item (row of data) and
        // the item index and should return null if the item is not
        // showing or return the group value
        var last_group = -1;
        var count = 0;
        for (var idx=0; idx < this.items.length; idx++)
        {
            const item = this.items[idx];
            const group = group_fn(item, idx);
            if (group === null || group === undefined) continue
            
            if (group != last_group) {
                ++count;
                last_group = group;
            }
            item._rowVariant = count % 2 == 0 ? variant : '';
        }
    }
}


class ChartVue {
    
    static svg_attrs(viewBox) {
        var attrs = {
            width: viewBox[2],
            height: viewBox[3],
            viewBox: viewBox.join(' '),
            style: 'overflow: visible',
            xmlns: 'http://www.w3.org/2000/svg'
        };
        return attrs;
    }

    static create_svg(create_fn, viewBox, children) {
        var svg = create_fn('svg', {
            attrs: ChartVue.svg_attrs(viewBox),
            children
        });
        return svg;
    }

    static add_yAxisLegend(g, data, colors) {
        //var gtick = g.select(".tick:last-of-type").append("g");
        const h = ChartPrefs.axis_font_size;
        var gtick = g.append("g")
            .attr('transform',
                  `translate(0, ${h * data.series.length})`);
        
        gtick.selectAll('rect')
            .data(data.series)
            .join('rect')
            .attr('x', 3)
            .attr('y', (d, i) => -h + i*h)
            .attr('width', h)
            .attr('height', h)
            .attr('fill', (d, i) => colors[i]);                
        gtick.selectAll('text')
            .data(data.series)
            .join('text')
            .attr('x', h + 6)
            .attr('y', (d, i) => i*h )
            .attr("text-anchor", "start")
            .attr("font-weight", "bold")
            .attr("fill", 'currentColor')
            .text(d => d.name);
        return g;
    }
};



/*
 * Timeseries data layout: {
 *   y: 'description',
 *   binsize: Number, // size in minutes,
 *   date_parse_format: '%Y-%m-%d',
 *   dates: [ 'YYYY-MM-DD HH:MM:SS', ... ],
 *   series: [
 *      {
 *         id: 'id',
 *         name: 'series 1 desc',
 *         values: [ Number, .... ]
 *      },
 *      {
 *         id: 'id',
 *         name: 'series 2 desc'
 *         values: [ ... ],
 *      }, 
 *      ...
 *   ]
 * }
 */    

class TimeseriesData {
    constructor(data) {
        Object.assign(this, data);
        this.convert_dates();
    }

    get_series(id) {
        for (var i=0; i<this.series.length; i++) {
            if (this.series[i].id == id) return this.series[i];
        }
    }

    dataView(desired_series_ids) {
        var dataview = Object.assign({}, this);
        dataview.series = [];
        
        var desired = {}
        desired_series_ids.forEach(id => desired[id] = true);
        this.series.forEach(s => {
            if (desired[s.id]) dataview.series.push(s);
        });
        return new TimeseriesData(dataview);
    }

    binsizeWithUnit() {
        // normalize binsize (which is a time span in minutes)
        const days = Math.floor(this.binsize / (24 * 60));
        const hours = Math.floor( (this.binsize - days*24*60) / 60 );
        const mins = this.binsize - days*24*60 - hours*60;
        if (days == 0 && hours == 0) {
            return {
                unit: 'minute',
                value: mins
            };
        }
        if (days == 0) {
            return {
                unit: 'hour',
                value: hours
            };
        }
        return {
            unit: 'day',
            value: days
        };
    }
    
    binsizeTimespan() {
        /* return the binsize timespan in seconds */
        return this.binsize * 60;
    }

    static binsizeOfRange(range) {
        // target 100-120 datapoints
        const target = 100;
        const tolerance = 0.2; // 20%
        
        if (typeof range[0] == 'string') {
            var parser = d3.utcParse('%Y-%m-%d %H:%M:%S');
            range = range.map(parser);
        }

        const span_min = Math.ceil(
            (range[1].getTime() - range[0].getTime()) / (1000*60*target)
        );
        const bin_days = Math.floor(span_min / (24*60));
        const bin_hours = Math.floor((span_min - bin_days*24*60) / 60);
        if (bin_days >= 1) {
            return bin_days * 24 * 60 +
                (bin_hours > (24 * tolerance) ? bin_hours*60: 0);
        }
        
        const bin_mins = span_min - bin_days*24*60 - bin_hours*60;
        if (bin_hours >= 1) {
            return bin_hours * 60 +
                (bin_mins > (60 * tolerance) ? bin_mins: 0 );
        }
        return bin_mins;
    }

    barwidth(xscale, barspacing) {
        /* get the width of a bar in a bar chart */
        var start = this.range[0];
        var end = this.range[1];
        var bins = (end.getTime() - start.getTime()) / (1000 * this.binsizeTimespan());
        return Math.max(1, (xscale.range()[1] - xscale.range()[0])/bins - (barspacing || 0));
    }

    formatDateTimeLong(d) {
        var options = { hour: 'numeric' };
        var b = this.binsizeWithUnit();
        if (b.unit === 'minute') {
            options.minute = 'numeric';
            return DateFormatter.dt_long(d, options);
        }
        if (b.unit === 'hour') {
            return DateFormatter.dt_long(d, options);
        }
        if (b.unit === 'day') {
            return DateFormatter.d_long(d);
        }
        throw new Error(`Unknown binsize unit: ${b.unit}`);
    }

    formatDateTimeShort(d) {
        var options = {
            year: 'numeric',
            month: 'numeric',
            day: 'numeric',
            weekday: undefined
        };
        var b = this.binsizeWithUnit();
        if (b.unit === 'minute') {
            Object.assign(options, {
                hour: 'numeric',
                minute: 'numeric'
            });
            return DateFormatter.dt_long(d, options);
        }
        if (b.unit === 'hour') {
            options.hour = 'numeric';
            return DateFormatter.dt_long(d, options);
        }
        if (b.unit === 'day') {
            return DateFormatter.d_short(d);
        }
        throw new Error(`Unknown binsize unit: ${b.unit}`);
    }

        
    convert_dates() {
        // all dates from the server are UTC strings
        // convert to Date objects
        if (this.dates.length > 0 && typeof this.dates[0] == 'string')
        {
            var parser = d3.utcParse(this.date_parse_format);
            this.dates = this.dates.map(parser);
        }
        if (this.range.length > 0 && typeof this.range[0] == 'string')
        {
            var parser = d3.utcParse(this.range_parse_format);
            this.range = this.range.map(parser);
        }        
    }
};


class ConnectionDisposition {
    constructor(disposition) {
        const data = {
            'failed_login_attempt': {
                short_desc: 'failed login attempt',
            },
            'insecure': {
                short_desc: 'insecure connection'
            },
            'ok': {
                short_desc: 'normal, secure connection'
            },
            'reject': {
                short_desc: 'mail attempt rejected'
            },
            'suspected_scanner': {
                short_desc: 'suspected scanner'
            }
        };        
        this.disposition = disposition;
        this.info = data[disposition];        
        if (! this.info) {
            this.info = {
                short_desc: disposition.replace('_',' ')
            }
        }
    }

    get short_desc() {
        return this.info.short_desc;
    }

    static formatter(disposition) {
        return new ConnectionDisposition(disposition).short_desc;
    }
};
