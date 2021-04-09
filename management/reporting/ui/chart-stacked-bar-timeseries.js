/*
 stacked bar chart
*/

Vue.component('chart-stacked-bar-timeseries', {
    props: {
        chart_data: { type:Object, required:false }, /* TimeseriesData */
        width: { type:Number, default: ChartPrefs.default_width },
        height: { type:Number, default: ChartPrefs.default_height },
    },
    
    render: function(ce) {
        return ChartVue.create_svg(ce, [0, 0, this.width, this.height]);
    },

    data: function() {
        return {
            tsdata: null,
            stacked: null,
            margin: {
                top: ChartPrefs.axis_font_size,
                bottom: ChartPrefs.axis_font_size*2,
                left: ChartPrefs.axis_font_size*3,
                right: ChartPrefs.axis_font_size
            },
            xscale: null,
            yscale: null,
            colors: ChartPrefs.colors, /* array of colors */
        };
    },

    mounted: function() {
        if (this.chart_data) {
            this.stack(this.chart_data);
            this.draw();
        }
    },

    watch: {
        'chart_data': function(newv, oldv) {
            this.stack(newv);
            this.draw();
        }
    },

    methods: {
        stack: function(data) {
            /* "stack" the data using d3.stack() */
            // 1. reorganize into the format stack() wants -- an
            // array of objects, with each object having a key of
            // 'date', plus one for each series
            var stacker_input = data.dates.map((d, i) => {
                var array_el = { date: d }
                data.series.forEach(s => {
                    array_el[s.name] = s.values[i];
                })
                return array_el;
            });
            
            // 2. call d3.stack() to get the stacking function, which
            // creates yet another version of the series data,
            // reformatted for more easily creating stacked bars.
            //
            // It returns a new array (see the d3 docs):
            // [
            //   [  /* series 1 */
            //      [ Number, Number, data: { date: Date } ],
            //      [ ... ], ...
            //   ],
            //   [  /* series 2 */
            //      [ Number, Number, data: { date: Date } ],
            //      [ ... ], ...
            //   ],
            //   ...
            // ]
            //
            var stacker = d3.stack()
                .keys(data.series.map(s => s.name))
                .order(d3.stackOrderNone)
                .offset(d3.stackOffsetNone);

            // 3. store the data
            this.tsdata = data;
            this.stacked = stacker(stacker_input);
        },
        

        draw: function() {
            const svg = d3.select(this.$el);
            svg.selectAll("g").remove();

            if (this.tsdata.dates.length == 0) {
                // no data ...
                svg.append("g")
                    .append("text")
                    .attr("font-family", ChartPrefs.default_font_family)
                    .attr("font-size", ChartPrefs.label_font_size)
                    .attr("text-anchor", "middle")
                    .attr("x", this.width/2)
                    .attr("y", this.height/2)
                    .text("no data");
            }
            
            this.xscale = d3.scaleTime()
                .domain(d3.extent(this.tsdata.dates))
                .nice()
                .range([this.margin.left, this.width - this.margin.right])
            
            var barwidth = this.tsdata.barwidth(this.xscale);
            var padding_x = barwidth / 2;
            var padding_y = ChartVue.get_yAxisLegendBounds(this.tsdata).height + 2;
            
            this.yscale = d3.scaleLinear()
                .domain([
                    0,
                    d3.sum(this.tsdata.series, s => d3.max(s.values))
                ])
                .range([
                    this.height - this.margin.bottom - padding_y,
                    this.margin.top,
                ]);

            var g = svg.append("g")
                .attr("transform", `translate(0, ${padding_y})`);

            g.append("g")
                .call(this.xAxis.bind(this, padding_x))
                .attr("font-size", ChartPrefs.axis_font_size);
            
            g.append("g")
                .call(this.yAxis.bind(this, padding_y))
                .attr("font-size", ChartPrefs.axis_font_size);

            for (var s_idx=0; s_idx<this.tsdata.series.length; s_idx++) {
                g.append("g")
                    .datum(s_idx)
                    .attr("fill", this.colors[s_idx])
                    .selectAll("rect")
                    .data(this.stacked[s_idx])
                    .join("rect")
                    .attr("x", d => this.xscale(d.data.date) - barwidth/2 + padding_x)
                    .attr("y", d => this.yscale(d[1]) + padding_y)
                    .attr("height", d => this.yscale(d[0]) - this.yscale(d[1]))
                    .attr("width", barwidth)
                    .call( hover.bind(this) )
                         
                    // .append("title")
                    // .text(d => `${this.tsdata.series[s_idx].name}: ${NumberFormatter.format(d.data[this.tsdata.series[s_idx].name])}`)
                ;
            }

            g.append("g")
                .attr("transform", `translate(${this.margin.left}, 0)`)
                .call(
                    g => ChartVue.add_yAxisLegend(g, this.tsdata, this.colors)
                );

            var hovinfo = g.append("g");

            function hover(rect) {
                if ("ontouchstart" in document) rect
                    .style("-webkit-tap-highlight-color", "transparent")
                    .on("touchstart", entered.bind(this))
                    .on("touchend", left)
                else rect
                    .on("mouseenter", entered.bind(this))
                    .on("mouseleave", left);

                function entered(event, d) {
                    var rect = d3.select(event.target)
                        .attr("fill", "#ccc");
                    var d = rect.datum();
                    var s_idx = d3.select(rect.node().parentNode).datum();
                    var s_name = this.tsdata.series[s_idx].name;
                    var v = d.data[s_name];
                    var x = Number(rect.attr('x')) + barwidth/2;
                    //var y = Number(rect.attr('y')) + Number(rect.attr('height'))/2;                 
                    var y = Number(rect.attr('y'));
                    hovinfo.attr(
                        "transform",
                        `translate( ${x}, ${y} )`)
                        .append('text')
                        .attr("font-family", ChartPrefs.default_font_family)
                        .attr("font-size", ChartPrefs.default_font_size)
                        .attr("text-anchor", "middle")
                        .attr("y", -3)
                        .text(`${this.tsdata.formatDateTimeShort(d.data.date)}`);
                    hovinfo.append("text")
                        .attr("font-family", ChartPrefs.default_font_family)
                        .attr("font-size", ChartPrefs.default_font_size)
                        .attr("text-anchor", "middle")
                        .attr("y", -3 - ChartPrefs.default_font_size)
                        .text(`${s_name} (${NumberFormatter.format(v)})`);

                }

                function left(event) {
                    d3.select(event.target).attr("fill", null);
                    hovinfo.selectAll("text").remove();
                }
            }
        },

        xAxis: function(padding, g) {
            var x = g.attr(
                'transform',
                `translate(${padding}, ${this.height - this.margin.bottom})`
            ).call(
                d3.axisBottom(this.xscale)
                    .ticks(this.width / 80)
                    .tickSizeOuter(0)
            );
            return x;
        },
        
        yAxis: function(padding, g) {
            var y = g.attr(
                "transform",
                `translate(${this.margin.left},${padding})`
            ).call(
                d3.axisLeft(this.yscale)
                    .ticks(this.height/50)
            ).call(
                g => g.select(".domain").remove()
            );
            
            return y;
        },

    }
});


