

Vue.component('capture-db-stats', {
    props: {
    },

    template:'<div>'+
        '<template v-if="stats">'+
           '<caption class="text-nowrap">Database date range</caption><div class="ml-2">First: {{stats.mta_connect.connect_time.min_str}}</div><div class="ml-2">Last: {{stats.mta_connect.connect_time.max_str}}</div>'+
           '<div class="mt-2">'+
           '  <b-table-lite small caption="Connections by disposition" caption-top :fields="row_counts.fields" :items=row_counts.items></b-table-lite>'+
           '</div>'+
        '</template>'+
        '<spinner v-else></spinner>'+
        '</div>'
    ,

    data: function() {
        return {
            stats: null,
            stats_time: null,
            row_counts: {}
        };
    },

    created: function() {
        this.getStats();
    },

    methods: {
        getStats: function() {
            axios.get('/reports/capture/db/stats')
                .then(response => {
                    this.stats = response.data;
                    this.stats_time = Date.now();

                    // convert dates
                    var parser = d3.utcParse(this.stats.date_parse_format);
                    [ 'min', 'max' ].forEach( k => {
                        var d = parser(this.stats.mta_connect.connect_time[k]);
                        this.stats.mta_connect.connect_time[k] = d;
                        this.stats.mta_connect.connect_time[k+'_str'] =
                            d==null ? '-' : DateFormatter.dt_long(d);
                    });

                    // make a small bvTable of row counts
                    this.row_counts = {
                        items: [],
                        fields: [ 'name', 'count', 'percent' ],
                        field_types: [
                            { type:'text/plain', label:'Disposition' },
                            'number/plain',
                            { type: 'number/percent', label:'Pct', places:1 },
                        ],
                    };
                    BvTable.setFieldDefinitions(
                        this.row_counts.fields,
                        this.row_counts.field_types
                    );
                    this.row_counts.fields[0].formatter = (v, key, item) => {
                        return new ConnectionDisposition(v).short_desc
                    };
                    this.row_counts.fields[0].tdClass = 'text-capitalize';


                    const total = this.stats.mta_connect.count;
                    for (var name in this.stats.mta_connect.disposition)
                    {
                        const count =
                              this.stats.mta_connect.disposition[name].count;
                        this.row_counts.items.push({
                            name: name,
                            count: count,
                            percent: count / total
                        });
                    }
                    this.row_counts.items.sort((a,b) => {
                        return a.count > b.count ? -1 :
                            a.count < b.count ? 1 : 0;
                    })
                    this.row_counts.items.push({
                        name:'Total',
                        count:this.stats.mta_connect.count,
                        percent:1,
                        '_rowVariant': 'primary'
                    });

                    
                })
                .catch(error => {
                    this.$root.handleError(error);
                });
        },
    }
});
