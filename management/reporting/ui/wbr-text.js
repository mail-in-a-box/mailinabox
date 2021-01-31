/*
 * This component adds <wbr> elements after all characters given by
 * `break_chars` in the given text.
 *
 * <wbr> enables the browser to wrap long text at those points
 * (without it the browser will only wrap at space and hyphen).
 *
 * Additionally, if `text_break_threshold` is greater than 0 and there
 * is a segment of text that exceeds that length, the bootstrap css
 * class "text-break" will be added to the <span>, which causes the
 * browser to wrap at any character of the text.
 */

Vue.component('wbr-text', {
    props: {
        text: { type:String, required: true },
        break_chars: { type:String, default:'@_.,:+=' },
        text_break_threshold: { type:Number, default:0 },
    },
    
    render: function(ce) {
        var children = [];
        var start=-1;
        var idx=0;
        var longest=-1;
        while (idx < this.text.length) {
            if (this.break_chars.indexOf(this.text[idx]) != -1) {
                var sliver = this.text.substring(start+1, idx+1);
                longest = Math.max(longest, sliver.length);
                children.push(sliver);
                children.push(ce('wbr'));
                start=idx;
            }
            idx++;
        }

        if (start < this.text.length-1) {
            var sliver = this.text.substring(start+1);
            longest = Math.max(longest, sliver.length);
            children.push(sliver);
        }
        
        var data = { };
        if (this.text_break_threshold>0 && longest>this.text_break_threshold)
            data['class'] = { 'text-break': true };
        return ce('span', data, children);
    }
});
