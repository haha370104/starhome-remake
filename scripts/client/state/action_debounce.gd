extends RefCounted

var _next_allowed_msec := 0


func try_begin(now_msec: int, interval_msec: int) -> bool:
	if now_msec < _next_allowed_msec:
		return false
	_next_allowed_msec = now_msec + interval_msec
	return true


func remaining_msec(now_msec: int) -> int:
	return maxi(0, _next_allowed_msec - now_msec)
