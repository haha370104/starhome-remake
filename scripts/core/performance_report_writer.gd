class_name PerformanceReportWriter
extends BackgroundFileWriter


## 在已有低优先级写入队列中完成百分位计算，避免周期性主线程排序尖刺。
## [param job] 已冻结的数值统计快照。
## 返回原子报告写入结果。
func _write_job(job: Dictionary) -> DomainResult:
	return AtomicJsonFile.write_document(job.path, build_report(job.document))


## 从环形采样计算最近窗口的百分位，并保留整轮累计统计。
## [param raw] 独立纯数据快照。
## 返回可序列化报告，单位为微秒。
static func build_report(raw: Dictionary) -> Dictionary:
	var rows := {}
	for metric: StringName in raw.durations:
		var sample: Dictionary = raw.durations[metric]
		var values: Array = sample.values.duplicate()
		values.sort()
		if values.is_empty(): continue
		rows[String(metric)] = {"count": sample.count, "window_samples": values.size(),
			"mean_usec": float(sample.total) / float(sample.count), "max_usec": sample.max,
			"p50_usec": values[ceili(values.size() * 0.50) - 1],
			"p95_usec": values[ceili(values.size() * 0.95) - 1],
			"p99_usec": values[ceili(values.size() * 0.99) - 1]}
	return {"schema_version": 1, "metadata": raw.metadata, "durations": rows,
		"counters": raw.counters, "gauges": raw.gauges,
		"percentile_scope": "latest 2048 samples per metric; count/mean/max cover the full run"}
