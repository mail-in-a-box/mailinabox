Vue.component('date-range-picker', {
    props: {
        start_range: [ String, Array ],  // "ytd", "mtd", "wtd", or [start, end] where start and end are strings in format YYYY-MM-DD in localti
        recall_id: String, // save / recall from localStorage
    },
    template: '<div class="d-flex align-items-center flex-wrap">'+
        '<div>Date range:<br><b-form-select v-model="range_type" :options="options" size="sm" @change="range_type_change"></b-form-select></div>'+
        '<div class="ml-2">From:<br><b-form-datepicker v-model="range[0]" style="max-width:20rem" :disabled="range_type != \'custom\'"></b-form-datepicker></div>' +
        '<div class="ml-2">To:<br><b-form-datepicker v-model="range[1]" style="max-width:20rem" :min="range[0]" :disabled="range_type != \'custom\'"></b-form-datepicker></div>' +
        '</div>'
    ,
    data: function() {
        var range_type = null;
        var range = null;
        var default_range_type = 'last30days';
        const recall_id_prefix = 'date-range-picker/';

        var v = null;
        if (typeof this.start_range === 'string') {
            if (this.start_range.substring(0,1) == '-') {
                default_range_type = this.start_range.substring(1);
            }
            else {
                v = this.validate_input_range(this.start_range);
            }
        }
        else {
            v = this.validate_input_range(this.start_range);
        }
        
        if (v) {
            // handles explicit valid "range-type", [ start, end ]
            range_type = v.range_type;
            range = v.range;
        }
        else if (this.recall_id) {
            const id = recall_id_prefix+this.recall_id;
            try {
                var v = JSON.parse(localStorage.getItem(id));
                range = v.range;
                range_type = v.range_type;
            } catch(e) {
                // pass
                console.error(e);
                console.log(localStorage.getItem(id));
            }
        }

        if (!range) {
            range_type = default_range_type;
            range = DateRange.rangeFromType(range_type)
                .map(DateFormatter.ymd);
        }
        
        return {
            recall_id_full:(this.recall_id ?
                            recall_id_prefix + this.recall_id :
                            null),
            range: range,
            range_type: range_type,
            options: [
                { value:'last7days', text:'Last 7 days' },
                { value:'last30days', text:'Last 30 days' },
                { value:'wtd', text:'Week-to-date' },
                { value:'mtd', text:'Month-to-date' },
                { value:'ytd', text:'Year-to-date' },
                { value:'custom', text:'Custom' }
            ],
        }
    },

    created: function() {
        this.notify_change(true);
    },

    watch: {
        'range': function() {
            this.notify_change();
        }
    },

    methods: {

        validate_input_range: function(range) {
            // if range is a string it's a range_type (eg "ytd")
            // othersize its an 2-element array [start, end] of dates
            // in YYYY-MM-DD (localtime) format
            if (typeof range == 'string') {
                var dates = DateRange.rangeFromType(range)
                    .map(DateFormatter.ymd);
                if (! range) return null;
                return { range:dates, range_type:range };
            }
            else if (range.length == 2) {
                var parser = d3.timeParse('%Y-%m-%d');
                if (! parser(range[0]) || !parser(range[1]))
                    return null;
                return { range, range_type:'custom' };
            }
            else {
                return null;
            }
        },

        set_range: function(range) {
            // if range is a string it's a range_type (eg "ytd")
            // othersize its an 2-element array [start, end] of dates
            // in YYYY-MM-DD (localtime) format
            var v = this.validate_input_range(range);
            if (!v) return false;
            this.range = v.range;
            this.range_type = v.range_type;
            this.notify_change();
            return true;
        },
        
        notify_change: function(init) {
            var parser = d3.timeParse('%Y-%m-%d');

            var end_utc = new Date();
            end_utc.setTime(
                parser(this.range[1]).getTime() + (24 * 60 * 60 * 1000)
            );
            var range_utc = [
                DateFormatter.ymdhms_utc(parser(this.range[0])),
                DateFormatter.ymdhms_utc(end_utc)
            ];
            
            this.$emit('change', {
                // localtime "YYYY-MM-DD" format - exactly what came
                // from the ui
                range: this.range,

                // convert localtime to utc, include hours. add 1 day
                // to end so that range_utc encompasses times >=start
                // and <end. save in the format "YYYYY-MM-DD HH:MM:SS"
                range_utc: range_utc,

                // 'custom', 'ytd', 'mtd', etc
                range_type: this.range_type,
                
                // just created, if true
                init: init || false,
            });
            
            if (this.recall_id_full) {
                localStorage.setItem(this.recall_id_full, JSON.stringify({
                    range: this.range,
                    range_type: this.range_type
                }));
            }
        },
        
        range_type_change: function(evt) {
            // ui select callback
            if (this.range_type == 'last7days')
                this.range = DateRange.lastXdays_as_ymd(7);
            else if (this.range_type == 'last30days')
                this.range = DateRange.lastXdays_as_ymd(30);
            else if (this.range_type == 'wtd')
                this.range = DateRange.wtd_as_ymd();
            else if (this.range_type == 'mtd')
                this.range = DateRange.mtd_as_ymd();
            else if (this.range_type == 'ytd')
                this.range = DateRange.ytd_as_ymd();
        },

    }
    
});

