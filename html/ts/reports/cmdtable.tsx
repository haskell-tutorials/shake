
function reportCmdTable(profile: Profile[], search: Prop<Search>): HTMLElement {
    const columns: Column[] =
        [ {field: "name", label: "Name", width: 200}
        , {field: "count", label: "Count", width: 75, alignRight: true, show: showInt}
        , {field: "total", label: "Total", width: 75, alignRight: true, show: showTime}
        , {field: "average", label: "Average", width: 75, alignRight: true, show: showTime}
        , {field: "max", label: "Max", width: 75, alignRight: true, show: showTime}
        ];
    return newTable(columns, search.map(cmdTableData));
}

function cmdTableData(search: Search): object[] {
    const res: MapString< {count: int, total: seconds, max: seconds} > = {};
    search.forEachProfile(p =>
        p.traces.forEach(t => {
            const time = t.stop - t.start;
            if (!(t.command in res))
                res[t.command] = {count: 1, total: time, max: time};
            else {
                const ans = res[t.command];
                ans.count++;
                ans.total += time;
                ans.max = Math.max(ans.max, time);
            }
        })
    );
    const res2 = [];
    for (const i in res)
        res2.push({name: i, average: res[i].total / res[i].count, ...res[i]});
    return res2;
}
