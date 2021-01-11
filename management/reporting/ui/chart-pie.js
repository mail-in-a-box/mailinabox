Vue.component('chart-pie', {
    /*
     * chart_data: [
     *   { name: 'name', value: value },
     *   ...
     * ]
     *
     * if prop `labels` is false, a legend is shown instead of
     * labeling each pie slice
     */
    props: {
        chart_data: Array,
        formatter: { type: Function, default: NumberFormatter.format },
        name_formatter: Function,
        labels: { type:Boolean, default: true },
        width: { type:Number, default: ChartPrefs.default_width },
        height: { type:Number, default: ChartPrefs.default_height },
    },
    
    render: function(ce) {
        var svg = ChartVue.create_svg(ce, [
            -this.width/2, -this.height/2, this.width, this.height
        ]);
        if (this.labels) {
            return svg;
        }

        /* 
      <div class="ml-1">
        <div v-for="d in legend">
          <span class="d-inline-block text-right pr-1 rounded" :style="{width:'5em','background-color':d.color}">{{d.value_str}}</span> {{d.name}}
        </div>
      </div>
        */
        var legend_children = [];
        this.legend.forEach(d => {
            var span = ce('span', { attrs: {
                'class': 'd-inline-block text-right pr-1 mr-1 rounded',
                'style': `width:5em; background-color:${d.color}`
            }}, this.formatter(d.value));

            legend_children.push(ce('div', [ span, d.name ]));
        });

        var div_legend = ce('div', { attrs: {
            'class': 'ml-1 mt-2'
        }}, legend_children);
        
        return ce('div', { attrs: {
            'class': "d-flex align-items-start"
        }}, [ svg, div_legend ]);

    },

    computed: {
        legend: function() {
            if (this.labels) {
                return null;
            }
            
            var legend = [];
            if (this.chart_data) {
                this.chart_data.forEach((d,i) => {
                    legend.push({
                        name: this.name_formatter ?
                            this.name_formatter(d.name) : d.name,
                        value: d.value,
                        color: this.colors[i % this.colors.length]
                    });
                });
            }
            legend.sort((a,b) => {
                return a.value > b.value ? -11 :
                    a.value < b.value ? 1 : 0;
            });
            return legend;
        }
    },

    data: function() {
        return {
            chdata: this.chart_data,
            colors: this.colors || ChartPrefs.colors,
        };
    },

    watch: {
        'chart_data': function(newval) {            
            this.chdata = newval;
            this.draw();
        }
    },

    mounted: function() {
        this.draw();
    },
        
    methods: {

        draw: function() {
            if (! this.chdata) return;
            
            var svg = d3.select(this.$el);
            if (! this.labels) svg = svg.select('svg');
            svg.selectAll("g").remove();

            var chdata = this.chdata;
            var nodata = false;
            if (d3.sum(this.chdata, d => d.value) == 0) {
                // no data
                chdata = [{ name:'no data', value:100 }]
                nodata = true;
            }

            const pie = d3.pie().sort(null).value(d => d.value);
            const arcs = pie(chdata);
            const arc = d3.arc()
                  .innerRadius(0)
                  .outerRadius(Math.min(this.width, this.height) / 2 - 1);

            var radius = Math.min(this.width, this.height) / 2;
            if (chdata.length == 1)
                radius *= 0.1;
            else if (chdata.length <= 3)
                radius *= 0.65;
            else if (chdata.length <= 6)
                radius *= 0.7;
            else
                radius *= 0.8;
            arcLabel = d3.arc().innerRadius(radius).outerRadius(radius);
            
            svg.append("g")
                .attr("stroke", "white")
                .selectAll("path")
                .data(arcs)
                .join("path")
                .attr("fill", (d,i) => this.colors[i % this.colors.length])
                .attr("d", arc)
                .append("title")
                .text(d => `${d.data.name}: ${this.formatter(d.data.value)}`);

            if (this.labels) {
                svg.append("g")
                    .attr("font-family", ChartPrefs.default_font_family)
                    .attr("font-size", ChartPrefs.label_font_size)
                    .attr("text-anchor", "middle")
                    .selectAll("text")
                    .data(arcs)
                    .join("text")
                    .attr("transform", d => `translate(${arcLabel.centroid(d)})`)
                    .call(text => text.append("tspan")
                          .attr("y", "-0.4em")
                          .attr("font-weight", "bold")
                          .text(d => d.data.name))
                    .call(text => text.filter(d => (d.endAngle - d.startAngle) > 0.25).append("tspan")
                          .attr("x", 0)
                          .attr("y", "0.7em")
                          .attr("fill-opacity", 0.7)
                          .text(d => nodata ? null : this.formatter(d.data.value)));
            }
        }

    },

});
