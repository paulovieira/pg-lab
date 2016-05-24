var pg = require('pg');
var math = require('mathjs');

var cn = 'postgres://user:password@localhost/dbname';
var poolSize = 10;
pg.defaults.poolSize = poolSize;

var numTrials = 10*poolSize;
var numDoneConnections = 0;

// time taken by pg.connect or client.connect
var waitingTime = [];

// next client will take between 1 to 2 ms to connect (after the previous
// client has connected); see the variable timeForNextConnection below
var timeForNextClient = [1, 2];

// main loop - use either "connectFromPool" or "connectWithNewClient" 
for (var i = 1; i <= numTrials; i++) {
    connectFromPool(i);
    //connectWithNewClient(i);
}


function connectFromPool(i) {

    var min = timeForNextClient[0];
    var max = timeForNextClient[1];
    var timeForNextConnection = i*Math.round(min + (max - min)*Math.random());

    setTimeout(function(){

        var start = Date.now();
        pg.connect(cn, function (err, client, done) {
    
            if (err) {
                throw err;
            }

            waitingTime.push(Date.now() - start);
            done();                

            numDoneConnections++;
            if (numDoneConnections === numTrials) {
                showStats("USING THE CLIENT POOL");
            }
        });

    }, timeForNextConnection);

}

function connectWithNewClient(i){

    var min = timeForNextClient[0];
    var max = timeForNextClient[1];
    var timeForNextConnection = i*Math.round(min + (max - min)*Math.random());

    setTimeout(function(){

        var client = new pg.Client(cn);

        var start = Date.now();
        client.connect(function(err){
    
            if (err) {
                throw err;
            }

            waitingTime.push(Date.now() - start);
            client.end();

            numDoneConnections++;
            if (numDoneConnections === numTrials) {
                showStats("USING NEW CLIENTS");
            }
        });

    }, timeForNextConnection);

}

function showStats(title){

    console.log("MEAN VALUE - " + title);
    console.log("global (all connections): ", math.mean(waitingTime));

    // statistics for each segment of the array (segment size === poolSize)
    var numSegments = waitingTime.length/poolSize;

    for(var i=0; i<numSegments; i++){

        var start = i*poolSize;
        var end = (i+1)*poolSize;
        var segment = waitingTime.slice(start, end);

        console.log("connections #" + start + " to #" + end + ": ", math.mean(segment));
    }

    pg.end();
}
