

begin
	
	import CSV
	import Gadfly
	import Gadfly.px
	import Cairo
	import Colors
	
	using DataFrames
	using Statistics
	using Formatting
	using Printf
	using Dates
	
end




(
	_dataset_path,
	_plot_path,
	_plot_format,
	_dataset_filter,
	_dataset_index,
	_dataset_metric,
) = ARGS

_dataset_filter = Symbol(_dataset_filter)
_dataset_index = Symbol(_dataset_index)
_dataset_metric = Symbol(_dataset_metric)
_plot_format = Symbol(_plot_format)




_dataset = CSV.read(
		_dataset_path,
		header = 1,
		normalizenames = true,
		delim = "\t", quotechar = '\0', escapechar = '\0',
		categorical = true,
		strict = true,
	)




_dataset = filter(
		(_data ->
			(_data[_dataset_index] !== missing) &&
			(_data[_dataset_metric] !== missing) &&
			(_data[_dataset_metric] != 0)),
		_dataset,
	)




if _dataset_filter == :world
	
	_dataset_location_key = :country
	_dataset_location_type = "total-world"
	_dataset_locations = ["World"]
	
elseif _dataset_filter == :global
	
	_dataset_location_key = :country
	_dataset_location_type = "total-country"
	_dataset_locations = [
			"China", "South Korea",
			"Italy", "Spain", "Germany", "France",
			"United States",
		]
	
elseif _dataset_filter == Symbol("europe-major")
	
	_dataset_location_key = :country
	_dataset_location_type = "total-country"
	_dataset_locations = [
			"China", "South Korea",
			"Italy", "Spain", "Germany", "France",
		]
	
elseif _dataset_filter == Symbol("europe-minor")
	
	_dataset_location_key = :country
	_dataset_location_type = "total-country"
	_dataset_locations = [
			"South Korea",
			"Italy", "Spain", "Germany", "France",
			"United Kingdom", "Switzerland",
		#	"Netherlands", "Austria", "Belgium",
		#	"Portugal", "Sweden", "Denmark",
		]
	
	_dataset = filter(
			(_data -> _data[_dataset_index] <= 30),
			_dataset,
		)
	
elseif _dataset_filter == :us
	
	_dataset_location_key = :province
	_dataset_location_type = "total-province"
	
	_dataset = filter(
			(_data ->
					(_data[:country] == "United States") &&
					(_data[:location_type] == _dataset_location_type) &&
					(_data[:province] != "(mainland)")),
			_dataset,
		)
	
	_dataset_locations = unique(_dataset[!, :province])
	
elseif _dataset_filter == :romania
	
	_dataset_location_key = :country
	_dataset_location_type = "total-country"
	_dataset_locations = [
			"Romania", "Hungary", "Bulgaria",
			"Italy", "Spain", "Germany", "France",
			"United Kingdom", "Austria",
		]
	
	_dataset = filter(
			(_data -> _data[_dataset_index] <= 20),
			_dataset,
		)
	
elseif _dataset_filter == :continents
	
	_dataset_location_key = :country
	_dataset_location_type = "total-region"
	_dataset_locations = [
			
			"Asia", "Europe", "Americas",
			"Oceania", "Africa",
			
		]
	
elseif _dataset_filter == :subcontinents
	
	_dataset_location_key = :country
	_dataset_location_type = "total-subregion"
	_dataset_locations = [
			"Western Asia", "Central Asia", "Southern Asia", "South-Eastern Asia", "Eastern Asia",
			"Western Europe", "Northern Europe", "Central Europe", "Southern Europe", "Eastern Europe",
			"North America", "Central America", "South America",
			"Western Africa", "Northern Africa", "Middle Africa", "Southern Africa", "Eastern Africa",
			"Australia and New Zealand", "Caribbean", "Melanesia", "Micronesia", "Polynesia",
		]
	
else
	throw(error(("[698e83db]", _dataset_filter)))
end




_dataset = filter(
		(_data -> _data[:location_type] == _dataset_location_type),
		_dataset,
	)

_dataset = filter(
		(_data -> _data[_dataset_location_key] in _dataset_locations),
		_dataset,
	)

_dataset_locations = unique(_dataset[!, _dataset_location_key])

_dataset_locations = filter(
		(_location -> size(filter((_data -> _data[_dataset_location_key] == _location), _dataset)[!, _dataset_metric])[1] >= 4),
		_dataset_locations,
	)

_dataset = filter(
		(_data -> _data[_dataset_location_key] in _dataset_locations),
		_dataset,
	)

_dataset_smoothing = 0.9




_dataset_min_date = minimum(_dataset[!, :date])
_dataset_max_date = maximum(_dataset[!, :date])
_dataset_max_index = maximum(_dataset[!, _dataset_index])

_dataset_min_metric = minimum(_dataset[!, _dataset_metric])
_dataset_max_metric = maximum(_dataset[!, _dataset_metric])
_dataset_delta_metric = abs(_dataset_max_metric - _dataset_min_metric)

_dataset_qmin_metric = quantile(_dataset[!, _dataset_metric], 0.01)
_dataset_qmax_metric = quantile(_dataset[!, _dataset_metric], 0.99)
_dataset_qdelta_metric = abs(_dataset_qmax_metric - _dataset_qmin_metric)


if true
	if abs(_dataset_min_metric - _dataset_qmin_metric) > (0.25 * _dataset_qdelta_metric)
		_dataset_min_metric = _dataset_qmin_metric - (0.25 * _dataset_qdelta_metric)
	end
	if abs(_dataset_max_metric - _dataset_qmax_metric) > (0.25 * _dataset_qdelta_metric)
		_dataset_max_metric = _dataset_qmax_metric + (0.25 * _dataset_qdelta_metric)
	end
else
	_dataset_min_metric = _dataset_qmin_metric - (0.25 * _dataset_qdelta_metric)
	_dataset_max_metric = _dataset_qmax_metric + (0.25 * _dataset_qdelta_metric)
end

_dataset_delta_metric = abs(_dataset_max_metric - _dataset_min_metric)


_dataset_cmin_metric = nothing
_dataset_cmax_metric = nothing

if _dataset_metric in [:relative_recovered, :relative_deaths, :relative_infected]
	_dataset_rstep_metric = maximum([10 ^ floor(log10(_dataset_delta_metric / 4)), 0.01])
	_dataset_cmin_metric = 0
	_dataset_cmax_metric = 100
	_dataset_rsuf_metric = "%"
elseif _dataset_metric in [:deltapct_confirmed, :deltapct_recovered, :deltapct_deaths, :deltapct_infected]
	_dataset_rstep_metric = maximum([10 ^ floor(log10(_dataset_delta_metric / 4)), 0.01])
	_dataset_rsuf_metric = "%"
else
	_dataset_rstep_metric = maximum([10 ^ floor(log10(_dataset_delta_metric / 4)), 0.01])
	_dataset_rsuf_metric = ""
end

while (_dataset_delta_metric / _dataset_rstep_metric) >= 12
	global _dataset_rstep_metric *= 2
	if (_dataset_rstep_metric >= 20000) && (_dataset_rstep_metric < 25000)
		_dataset_rstep_metric = 25000
	elseif (_dataset_rstep_metric > 10000) && (_dataset_rstep_metric < 20000)
		_dataset_rstep_metric = 10000
	elseif (_dataset_rstep_metric >= 2000) && (_dataset_rstep_metric < 2500)
		_dataset_rstep_metric = 2500
	elseif (_dataset_rstep_metric > 1000) && (_dataset_rstep_metric < 2000)
		_dataset_rstep_metric = 1000
	elseif (_dataset_rstep_metric >= 200) && (_dataset_rstep_metric < 250)
		_dataset_rstep_metric = 250
	elseif (_dataset_rstep_metric > 100) && (_dataset_rstep_metric < 200)
		_dataset_rstep_metric = 100
	elseif (_dataset_rstep_metric >= 20) && (_dataset_rstep_metric < 25)
		_dataset_rstep_metric = 25
	elseif (_dataset_rstep_metric > 10) && (_dataset_rstep_metric < 20)
		_dataset_rstep_metric = 10
	elseif (_dataset_rstep_metric >= 2.0) && (_dataset_rstep_metric < 2.5)
		_dataset_rstep_metric = 2.5
	elseif (_dataset_rstep_metric > 1.0) && (_dataset_rstep_metric < 2.0)
		_dataset_rstep_metric = 1.0
	elseif (_dataset_rstep_metric >= 0.20) && (_dataset_rstep_metric < 0.25)
		_dataset_rstep_metric = 0.25
	elseif (_dataset_rstep_metric > 0.10) && (_dataset_rstep_metric < 0.20)
		_dataset_rstep_metric = 0.10
	elseif (_dataset_rstep_metric >= 0.020) && (_dataset_rstep_metric < 0.025)
		_dataset_rstep_metric = 0.025
	elseif (_dataset_rstep_metric > 0.010) && (_dataset_rstep_metric < 0.020)
		_dataset_rstep_metric = 0.010
	end
end

if _dataset_rstep_metric != floor(_dataset_rstep_metric)
	_dataset_rprec_metric = 2
else
	_dataset_rprec_metric = 0
end


_dataset_rmin_metric = floor(_dataset_min_metric / _dataset_rstep_metric) * _dataset_rstep_metric
_dataset_rmax_metric = ceil(_dataset_max_metric / _dataset_rstep_metric) * _dataset_rstep_metric

if _dataset_cmin_metric !== nothing
	_dataset_rmin_metric = maximum([_dataset_rmin_metric, _dataset_cmin_metric])
end
if _dataset_cmax_metric !== nothing
	_dataset_rmax_metric = minimum([_dataset_rmax_metric, _dataset_cmax_metric])
end




_dataset_locations_allowed = [
		
		"World",
		
		"China", "South Korea", "United States", "Iran",
		"Italy", "Spain", "Germany", "France",
		"United Kingdom", "Switzerland", "Netherlands", "Austria", "Belgium", "Portugal", "Sweden", "Denmark",
		"Romania", "Hungary", "Bulgaria",
		
		"Asia", "Europe", "Americas", "Oceania", "Africa",
		"Western Asia", "Central Asia", "Southern Asia", "South-Eastern Asia", "Eastern Asia",
		"Western Europe", "Northern Europe", "Central Europe", "Southern Europe", "Eastern Europe",
		"North America", "Central America", "South America",
		"Western Africa", "Northern Africa", "Middle Africa", "Southern Africa", "Eastern Africa",
		"Australia and New Zealand", "Caribbean", "Melanesia", "Micronesia", "Polynesia",
		
		"Arizona", "California", "Colorado", "Connecticut", "Florida", "Georgia", "Illinois", "Indiana",
		"Louisiana", "Maryland", "Massachusetts", "Michigan", "Minnesota", "Mississippi", "Nevada",
		"New Jersey", "New York", "North Carolina", "Ohio", "Pennsylvania", "South Carolina", "Tennessee",
		"Texas", "Utah", "Virginia", "Washington", "Wisconsin",
		
	]

_dataset_locations_allowed = filter(
		(_location -> _location in _dataset_locations),
		_dataset_locations_allowed,
	)

for _dataset_location in _dataset_locations
	if ! (_dataset_location in _dataset_locations_allowed)
		println(("[99218dd5]", _dataset_location))
		throw(error(("[99218dd5]", _dataset_location)))
	end
end




_dataset_locations_meta = DataFrame(
		location = String[],
		label = String[],
		color = Colors.Colorant[],
		day_index_max = Int[],
		day_metric_max = Number[],
		day_date_max = Date[],
	)

_dataset_locations_count = size(_dataset_locations_allowed)[1]

if false
	_dataset_colors_increment = 15
	_dataset_colors_delta = _dataset_colors_increment
	while ((_dataset_colors_delta + _dataset_colors_increment) * _dataset_locations_count) < 360
		global _dataset_colors_delta += _dataset_colors_increment
	end
	if (_dataset_colors_delta * _dataset_locations_count) >= 360
		println(("[28e552a2]", _dataset_colors_delta, _dataset_locations_count))
	end
else
	_dataset_colors_delta = floor(360 / _dataset_locations_count)
end

for (_index, _dataset_location) in enumerate(_dataset_locations_allowed)
	_dataset_0 = filter((_data -> _data[_dataset_location_key] == _dataset_location), _dataset)
	_dataset_max_index =  findmax(_dataset_0[:, _dataset_index])
	_dataset_max_metric = findmax(_dataset_0[:, _dataset_metric])
	_dataset_max_date = findmax(_dataset_0[:, :date])
	_dataset_label = (
			_dataset_location * "\n" *
			(format(_dataset_max_metric[1], commas = true, precision = _dataset_rprec_metric) * _dataset_rsuf_metric)
		)
	
	_dataset_color = Colors.HSL(
			(_index - 1) * _dataset_colors_delta,
			1,
			0.5,
		)
	
	_dataset_location_meta = (
			_dataset_location,
			_dataset_label,
			_dataset_color,
			_dataset_max_index[1],
			_dataset_max_metric[1],
			_dataset_max_date[1],
		)
	push!(_dataset_locations_meta, _dataset_location_meta)
end




Gadfly.push_theme(:dark)

_plot_font_name = "JetBrains Mono"
_plot_font_size = 12px

_plot_style = Gadfly.style(
		point_size = 2px,
		line_width = 2px,
		highlight_width = 1px,
		grid_line_width = 1px,
		grid_color = Colors.parse(Colors.Colorant, "hsl(0, 0%, 25%)"),
		major_label_font = _plot_font_name,
		major_label_font_size = _plot_font_size * 1.0,
		major_label_color = Colors.parse(Colors.Colorant, "hsl(0, 0%, 75%)"),
		minor_label_font = _plot_font_name,
		minor_label_font_size = _plot_font_size * 0.8,
		minor_label_color = Colors.parse(Colors.Colorant, "hsl(0, 0%, 75%)"),
		point_label_font = _plot_font_name * " Bold",
		point_label_font_size = _plot_font_size * 0.8,
		point_label_color = Colors.parse(Colors.Colorant, "hsl(0, 0%, 100%)"),
		key_title_font = _plot_font_name,
		key_title_font_size = 0px,
		key_title_color = Colors.parse(Colors.Colorant, "hsl(0, 0%, 75%)"),
		key_label_font = _plot_font_name,
		key_label_font_size = _plot_font_size * 0.8,
		key_label_color = Colors.parse(Colors.Colorant, "hsl(0, 0%, 75%)"),
		key_position = :right,
		key_max_columns = 16,
		colorkey_swatch_shape = :circle,
		discrete_highlight_color = (_ -> nothing),
		panel_fill = nothing,
		panel_stroke = nothing,
		plot_padding = [16px],
		background_color = Colors.parse(Colors.Colorant, "hsl(0, 0%, 5%)"),
		default_color = Colors.parse(Colors.Colorant, "hsl(0, 100%, 100%)"),
	)


_plot_line_filter = (
		startswith("deltapct_", String(_dataset_metric)) ||
		false
	)




_plot = Gadfly.plot(
		
#		Gadfly.layer(
#			_dataset_locations_meta,
#			x = :day_index_max,
#			y = :day_metric_max,
#			label = :label,
#			color = :location,
#			Gadfly.Geom.label(position = :dynamic, hide_overlaps = true),
#		),
		
		Gadfly.layer(
			_dataset,
			x = _dataset_index,
			y = _dataset_metric,
			color = _dataset_location_key,
			Gadfly.Geom.point,
		),
		
		Gadfly.layer(
			filter((_data -> !_plot_line_filter || (_data[_dataset_metric] >= _dataset_qmin_metric) && (_data[_dataset_metric] <= _dataset_qmax_metric)), _dataset),
			x = _dataset_index,
			y = _dataset_metric,
			color = _dataset_location_key,
			if _dataset_smoothing !== nothing
				Gadfly.Geom.smooth(method = :loess, smoothing = _dataset_smoothing)
			else
				Gadfly.Geom.line
			end,
		),
		
		Gadfly.Coord.cartesian(xmin = 1, xmax = _dataset_max_index, ymin = _dataset_rmin_metric, ymax = _dataset_rmax_metric),
		Gadfly.Scale.x_continuous(format = :plain, labels = (_value -> @sprintf("%d", _value))),
		Gadfly.Scale.y_continuous(format = :plain, labels = (_value -> format(_value, commas = true, precision = _dataset_rprec_metric) * _dataset_rsuf_metric)),
		
		Gadfly.Guide.title(@sprintf("JHU CSSE COVID-19 dataset -- `%s` per `%s` (until %s)", _dataset_metric, _dataset_index, _dataset_max_date)),
		Gadfly.Guide.xlabel(nothing),
		Gadfly.Guide.ylabel(nothing),
		
		Gadfly.Guide.xticks(ticks =
				if (_dataset_max_index > 20)
					[1; 5 : 5 : _dataset_max_index;]
				else
					[1 : _dataset_max_index;]
				end),
		Gadfly.Guide.yticks(ticks = [_dataset_rmin_metric : _dataset_rstep_metric : _dataset_rmax_metric;]),
		
		Gadfly.Scale.color_discrete_manual(_dataset_locations_meta[:, :color]..., levels = _dataset_locations_meta[:, :location]),
		_plot_style,
	)




if _plot_format == :pdf
	_plot_output = Gadfly.PDF(_plot_path, 800px, 400px)
else
	throw(error(("[14de0af5]", _plot_format)))
end

Gadfly.draw(_plot_output, _plot)

