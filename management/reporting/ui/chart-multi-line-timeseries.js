import { ChartPrefs, NumberFormatter, ChartVue } from "./charting.js";

export default Vue.component('chart-multi-line-timeseries', {
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
            tsdata: this.chart_data,
            margin: {
                top: ChartPrefs.axis_font_size,
                bottom: ChartPrefs.axis_font_size * 2,
                left: ChartPrefs.axis_font_size *3,
                right: ChartPrefs.axis_font_size
            },
            xscale: null,
            yscale: null,
            colors: ChartPrefs.line_colors
        };
    },

    watch: {
        'chart_data': function(newval) {            
            this.tsdata = newval;
            this.draw();
        }
    },

    mounted: function() {
        this.draw();
    },
        
    methods: {

        draw: function() {
            if (! this.tsdata) {
                return;
            }
            
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

            this.yscale = d3.scaleLinear()
                .domain([
                    d3.min(this.tsdata.series, d => d3.min(d.values)),
                    d3.max(this.tsdata.series, d => d3.max(d.values))
                ])
                .nice()
                .range([this.height - this.margin.bottom, this.margin.top])
            
            svg.append("g")
                .call(this.xAxis.bind(this))
                .attr("font-size", ChartPrefs.axis_font_size);

            svg.append("g")
                .call(this.yAxis.bind(this))
                .attr("font-size", ChartPrefs.axis_font_size);

            if (this.tsdata.dates.length == 1) {
                // special case
                const g = svg.append("g")
                      .selectAll("circle")
                      .data(this.tsdata.series)
                      .join("circle")
                      .attr("fill", (d, i) => this.colors[i])
                      .attr("cx", this.xscale(this.tsdata.dates[0]))
                      .attr("cy", d => this.yscale(d.values[0]))
                      .attr("r", 2.5);
                this.hover(svg, g);
            }
            else {
                const line = d3.line()
                      .defined(d => !isNaN(d))
                      .x((d, i) => this.xscale(this.tsdata.dates[i]))
                      .y(d => this.yscale(d));
                
                const path = svg.append("g")
                      .attr("fill", "none")
                      .attr("stroke-width", 1.5)
                      .attr("stroke-linejoin", "round")
                      .attr("stroke-linecap", "round")
                      .selectAll("path")
                      .data(this.tsdata.series)
                      .join("path")
                      .style("mix-blend-mode", "multiply")
                      .style("stroke", (d, i) => this.colors[i])
                      .attr("d", d => line(d.values))
                ;
                
                svg.call(this.hover.bind(this), path);
            }
        },

        xAxis: function(g) {
            var x = g.attr(
                'transform',
                `translate(0, ${this.height - this.margin.bottom})`
            ).call(
                d3.axisBottom(this.xscale)
                    .ticks(this.width / 80)
                    .tickSizeOuter(0)
            );
            return x;
        },
        
        yAxis: function(g) {
            var y = g.attr(
                "transform",
                `translate(${this.margin.left},0)`
            ).call(
                d3.axisLeft(this.yscale)
                    .ticks(this.height/50)
            ).call(
                g => g.select(".domain").remove()
            ).call( 
                g => ChartVue.add_yAxisLegend(g, this.tsdata, this.colors)
            );
            return y;
        },

        hover: function(svg, path) {
            if ("ontouchstart" in document) svg
                .style("-webkit-tap-highlight-color", "transparent")
                .on("touchmove", moved.bind(this))
                .on("touchstart", entered)
                .on("touchend", left)
            else svg
                .on("mousemove", moved.bind(this))
                .on("mouseenter", entered)
                .on("mouseleave", left);

            const dot = svg.append("g")
                  .attr("display", "none");

            dot.append("circle")
                .attr("r", 2.5);

            dot.append("text")
                .attr("font-family", ChartPrefs.default_font_family)
                .attr("font-size", ChartPrefs.default_font_size)
                .attr("text-anchor", "middle")
                .attr("y", -8);

            function moved(event) {
                if (!event) event = d3.event;
                event.preventDefault();
                var pointer;
                if (d3.pointer)
                    pointer = d3.pointer(event, svg.node());
                else
                    pointer = d3.mouse(svg.node());
                const xvalue = this.xscale.invert(pointer[0]); // date
                const yvalue = this.yscale.invert(pointer[1]); // number
                //const i = d3.bisectCenter(this.tsdata.dates, xvalue); // index
                var i = d3.bisect(this.tsdata.dates, xvalue); // index
                if (i<0 || i > this.tsdata.dates.length) return;
                i = Math.min(this.tsdata.dates.length-1, i);
                         
                // closest series
                var closest = null;
                for (var sidx=0; sidx<this.tsdata.series.length; sidx++) {
                    var v = Math.abs(this.tsdata.series[sidx].values[i] - yvalue);
                    if (closest === null || v<closest.val) {
                        closest = {
                            sidx: sidx,
                            val: v
                        };
                    }
                }
                const s = this.tsdata.series[closest.sidx];
                if (i<0 || i>= s.values.length) {
                    dot.attr("display", "none");
                    return;
                }
                else {
                    dot.attr("display", null);
                    path.attr("stroke", d => d === s ? null : "#ddd")
                        .filter(d => d === s).raise();
                    dot.attr(
                        "transform",
                        `translate(${this.xscale(this.tsdata.dates[i])},${this.yscale(s.values[i])})`
                    );
                    dot.select("text").text(`${this.tsdata.formatDateTimeShort(this.tsdata.dates[i])} (${NumberFormatter.format(s.values[i])})`);
                }
            }

            function entered() {
                path.style("mix-blend-mode", null).attr("stroke", "#ddd");
                //dot.attr("display", null);
            }
            
            function left() {
                path.style("mix-blend-mode", "multiply").attr("stroke", null);
                dot.attr("display", "none");
            }
        }
    }
});


