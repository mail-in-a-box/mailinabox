export default Vue.component('chart-table', {
    props: {
        items: Array,
        fields: Array,
        caption: String
    },

    /* <b-table-lite striped small :fields="fields_x" :items="items" caption-top><template #table-caption><span class="text-nowrap">{{caption}}</span></template></b-table>*/
    render: function(ce) {
        var scopedSlots= {
            'table-caption': props =>
                ce('span', { class: { 'text-nowrap':true }}, this.caption)
        };
        if (this.$scopedSlots) {
            for (var slotName in this.$scopedSlots) {
                scopedSlots[slotName] = this.$scopedSlots[slotName];
            }
        }
        var table = ce('b-table-lite', {
            props: {
                'striped': true,
                'small': true,
                'fields': this.fields_x,
                'items': this.items,
                'caption-top': true
            },
            attrs: {
                'thead-tr-class': 'h-1'
            },
            scopedSlots: scopedSlots
        });
        
        return table;
    },

    computed: {
        fields_x: function() {
            if (this.items.length == 0) {
                return [{
                    key: 'no data',
                    thClass: 'text-nowrap'
                }];
            }
            return this.fields;
        }
    }

});
