let Fs = require('fs');
let { createPool, sql } = require('slonik');

let connectionString = Fs.readFileSync('connection-string.txt', 'utf8');

let interceptors = [{
	/*
	afterPoolConnection: (arg0, arg1, arg2) => {

		console.log('INTERCEPTOR: afterPoolConnection')
		console.log(arg0);
		console.log(arg1);
		console.log(arg2);
	},
	*/
	/*
	afterQueryExecution: (arg0, arg1, arg2) => {

		console.log('INTERCEPTOR: afterQueryExecution')
		console.log(arg0);
		console.log(arg1);
		console.log(arg2);
	},
	*/
	/*
	beforePoolConnection: (arg0, arg1, arg2) => {

		console.log('INTERCEPTOR: beforePoolConnection')
		console.log(arg0);
		console.log(arg1);
		console.log(arg2);
	},
	beforePoolConnectionRelease: (arg0, arg1, arg2) => {

		console.log('INTERCEPTOR: beforePoolConnectionRelease')
		console.log(arg0);
		console.log(arg1);
		console.log(arg2);
	},
	beforeQueryExecution: (arg0, arg1, arg2) => {

		console.log('INTERCEPTOR: beforeQueryExecution')
		console.log(arg0);
		console.log(arg1);
		console.log(arg2);
	},
	queryExecutionError: (arg0, arg1, arg2) => {

		console.log('INTERCEPTOR: queryExecutionError')
		console.log(arg0);
		console.log(arg1);
		console.log(arg2);
	},
	transformQuery: () => {

		console.log('INTERCEPTOR: transformQuery')
		console.log(arg0);
		console.log(arg1);
		console.log(arg2);
	},
	*/
	transformRow: (queryContext, query, row, fields) => {

		console.log('INTERCEPTOR: transformRow')

		delete row.id;
		row.xyz = 123;
		return row;

	},
	
}];
let pool = createPool(connectionString, {
	interceptors
});

let id = 43;
let x2, x3;

let params = {};
/*
let queryText = `
select
    id,
    name,
    name_original,
    user_id,
    municipality_id,
    good_practice_id,
    initiative_id,
    description,
    partition,
    seq_order
from t_files
where id = :id
`;
*/
let whereConditions = [sql`TRUE`];

let something1 = false;
if (something1) {
	let user_id = 15;
	whereConditions.push(sql`user_id = ${ user_id }`);
}

let something2 = true;
if (something2) {
	let id = 67;
	whereConditions.push(sql`id = ${ id }`);
}

let query = sql`
select
    id,
    name,
    user_id,
    municipality_id,
    good_practice_id,
    initiative_id,
    description,
    partition,
    seq_order
from t_files
where ${ sql.booleanExpression(whereConditions, 'AND') }
`;


console.log(`
---
${ JSON.stringify(query, null, 2) }
---
`)
Promise.resolve()
	.then(() => {

		return pool.query(query)
	})
	.then(response => {

		//console.log(response)
		let { rowCount, rows } = response;
		console.log(rowCount)
		console.log(rows)
	})
	.then(() => {


		return pool.any(query)
	})
	.then(response => {

		console.log('xxxxxxxxxxxxxxxxxxxxxxxxxx')
		console.log(response)
	})
	.catch(err => {


		console.log('err: ', err)
	})

