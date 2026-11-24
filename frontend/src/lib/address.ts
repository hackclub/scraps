export interface ShippingAddress {
	firstName: string;
	lastName: string;
	address1: string;
	address2: string | null;
	city: string;
	state: string;
	postalCode: string;
	country: string;
	phone: string | null;
}

type AddressLines = Pick<
	ShippingAddress,
	'address1' | 'address2' | 'city' | 'state' | 'postalCode' | 'country'
>;

export function parseShippingAddress(raw: string | null): ShippingAddress | null {
	if (!raw) return null;
	try {
		return JSON.parse(raw);
	} catch {
		return null;
	}
}

export function addressKey(a: Partial<AddressLines> | null): string {
	if (!a) return '';
	return [a.address1, a.address2, a.city, a.state, a.postalCode, a.country]
		.map((v) => (v ?? '').trim().toLowerCase())
		.join('|');
}

export function formatAddressLine(a: Partial<AddressLines>): string {
	return [a.address1, a.address2, a.city, a.state, a.postalCode, a.country]
		.filter(Boolean)
		.join(', ');
}

export function orderVerb(
	orderType: string,
	labels: { orderBought: string; orderWon: string; orderConsolation: string }
): string {
	if (orderType === 'purchase') return labels.orderBought;
	if (orderType === 'luck_win' || orderType === 'gachapon') return labels.orderWon;
	if (orderType === 'consolation') return labels.orderConsolation;
	return orderType;
}

export interface AddressConflict {
	id: number;
	itemName: string;
	orderType: string;
	createdAt: string;
	isFulfilled: boolean;
	address: string;
}

export interface PastOrder {
	id: number;
	status: string;
	orderType: string;
	createdAt: string;
	isFulfilled: boolean;
	itemName: string;
	shippingAddress: string | null;
}

export function findAddressConflicts(
	current: Partial<AddressLines> | null,
	orders: PastOrder[],
	excludeOrderId?: number
): AddressConflict[] {
	const key = addressKey(current);
	if (!key) return [];
	return orders.flatMap((o) => {
		if (o.id === excludeOrderId || o.status === 'cancelled' || o.status === 'deleted') return [];
		const a = parseShippingAddress(o.shippingAddress);
		const otherKey = addressKey(a);
		if (!a || !otherKey || otherKey === key) return [];
		return [
			{
				id: o.id,
				itemName: o.itemName,
				orderType: o.orderType,
				createdAt: o.createdAt,
				isFulfilled: o.isFulfilled,
				address: formatAddressLine(a)
			}
		];
	});
}
