#### Benchmark for the `pg` module

Connecting using the client pool (`pg.connect`) vs creating a new client and making a direct connection (`client.connect`).

Results: 

```sh
MEAN VALUE - USING THE CLIENT POOL
global (all connections):  1.9
connections #0 to #10:  14.2
connections #10 to #20:  4.5
connections #20 to #30:  0.2
connections #30 to #40:  0
connections #40 to #50:  0
connections #50 to #60:  0
connections #60 to #70:  0
connections #70 to #80:  0
connections #80 to #90:  0
connections #90 to #100:  0.1
```


```sh
MEAN VALUE - USING NEW CLIENTS
global (all connections):  22.86
connections #0 to #10:  25
connections #10 to #20:  29.2
connections #20 to #30:  31.4
connections #30 to #40:  30.9
connections #40 to #50:  30.9
connections #50 to #60:  29.5
connections #60 to #70:  26.1
connections #70 to #80:  18.1
connections #80 to #90:  4.9
connections #90 to #100:  2.6
```

