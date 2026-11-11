--!strict

export type Transform = (current: any?) -> any?

export type Interface = {
	UpdateAsync: (self: Interface, key: string, transform: Transform) -> (boolean, any?, string?),
}

return {}
