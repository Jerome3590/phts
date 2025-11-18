# -*- coding: utf-8 -*-
"""
Created on Fri May 28 11:33:26 2021

@author: zlzl95
"""

import tensorflow as tf
import tensorflow.keras.backend as tfkb
import numpy as np

def loss_lik_efron(y_true, y_pred):
    
    y_true = tf.cast(y_true, tf.float32)
    y_pred = tf.cast(y_pred, tf.float32)
    y_pred = tfkb.flatten(y_pred)
    
    time = tfkb.flatten(y_true[:,0])
    event = tfkb.flatten(y_true[:,1])
    
# =============================================================================
#    For test
#    time = y_dat[:,0]
#    event = y_dat[:,1]
#    event[0] = 1
#    time[0] = time[619]
#     
#    y_pred = y_val[:,0]
# =============================================================================
    
    n = tf.shape(time)[0]
    sort_index = tf.math.top_k(time, k = n, sorted = True).indices
    time = tfkb.gather(reference = time, indices = sort_index)
    event = tfkb.gather(reference = event, indices = sort_index)
    y_pred = tfkb.gather(reference = y_pred, indices = sort_index)
    
    time = tfkb.reverse(time, axes = 0)
    event = tfkb.reverse(event, axes = 0)
    y_pred = tfkb.reverse(y_pred, axes = 0)
    
    time_event = time * event
    unique_ftime = tf.unique(tf.boolean_mask(tensor = time_event, mask = tf.greater(time_event, 0))).y
    m = tf.shape(unique_ftime)[0]
    tie_count = tf.unique_with_counts(tf.boolean_mask(time_event, tf.greater(time_event, 0))).count
    ind_matrix = tfkb.expand_dims(time, 0) - tfkb.expand_dims(time, 1)
    ind_matrix = tfkb.equal(x = ind_matrix, y = tfkb.zeros_like(ind_matrix))
    ind_matrix = tfkb.cast(x = ind_matrix, dtype = tf.float32)
     
    time_count = tfkb.cumsum(tf.unique_with_counts(time).count)
    time_count = tfkb.cast(time_count - tfkb.ones_like(time_count), dtype = tf.int32)
    ind_matrix = tfkb.gather(ind_matrix, time_count)
    
    tie_haz = tfkb.exp(y_pred) * event
    tie_haz = tfkb.dot(ind_matrix, tfkb.expand_dims(tie_haz))
    event_index = tf.math.not_equal(tie_haz,0)
    tie_haz = tf.boolean_mask(tie_haz, event_index)
  
    tie_risk = y_pred * event
    tie_risk = tfkb.dot(ind_matrix, tfkb.expand_dims(tie_risk))
    tie_risk = tf.boolean_mask(tie_risk, event_index)
  
    cum_haz = tfkb.dot(ind_matrix, tfkb.expand_dims(tfkb.exp(y_pred)))
    cum_haz = tfkb.reverse(tf.cumsum(tfkb.reverse(cum_haz, axes = 0)), axes = 0)
    cum_haz = tf.boolean_mask(cum_haz, event_index)
    
    likelihood = tf.Variable(0., trainable = False) 
    j = tf.cast(0, dtype = tf.int32)
    
    def loop_cond(j,*arg):
        return (j < m)
    
    def loop_body(j,tc,tr,th,ch,lik):
        l = tc[j]
        l = tfkb.cast(l, dtype = tf.float32)
        J = tf.linspace(start = tf.cast(0, tf.float32), stop = l-1, num = tf.cast(l, tf.int32))/l 
        Dm = ch[j] - J*th[j]
    
        lik = lik + tr[j] - tf.math.reduce_sum(tf.math.log(Dm))
    
        one = tfkb.ones_like(j)
        j_new = j + one
        return j_new, tc, tr, th, ch, lik

    loop_out = tf.while_loop(cond = loop_cond, body = loop_body,
                          loop_vars = [j, tie_count, tie_risk, tie_haz, cum_haz, likelihood])
    log_lik = loop_out[len(loop_out)-1]

    return tf.negative(log_lik)

def base_efron(y_test, y_test_pred):

    #   For test
# =============================================================================
#     y_test = y_dat
#     y_test_pred = y_val[:,0]
# =============================================================================
    if tf.is_tensor(y_test):
        y_test = y_test.numpy()
        
    if tf.is_tensor(y_test_pred):
        y_pred = y_test_pred.numpy()
    else:
        y_pred = y_test_pred
        
    time = y_test[:,0]
    event = y_test[:,1]
        
    n = time.shape[0]
    sort_index = np.argsort(time)
    time = np.take(time, indices = sort_index)
    event = np.take(event, indices = sort_index)
    y_pred = np.take(y_pred, indices = sort_index)    
    
    time_event = time*event
    unique_ftime, tie_count = np.unique(time_event[time_event != 0], return_counts=True)
    m = len(unique_ftime)
    
    ind_matrix = np.array([time,]*n).transpose()-np.array([time,]*n)
    ind_matrix = (ind_matrix == 0)*1
    
    _,time_count = np.unique(time,return_counts=True)
    time_count = np.cumsum(time_count)
    ind_matrix = ind_matrix[time_count-1,]
    
    tie_haz = np.exp(y_pred)*event
    tie_haz = np.dot(ind_matrix,tie_haz)
    event_index = np.where(tie_haz!=0)
    tie_haz = tie_haz[event_index]
    
    cum_haz = np.dot(ind_matrix,np.exp(y_pred))
    cum_haz = np.cumsum(cum_haz[::-1])[::-1]
    cum_haz = cum_haz[event_index]

    def basehaz(x):
        l = tie_count[x]
        J = np.array(range(l))/l
        Dm = cum_haz[x]-J*tie_haz[x]
        Dm = 1/Dm
        Dm = sum(Dm)
        return Dm

    base_haz = np.array([basehaz(xi) for xi in range(m)])
    base_haz = np.cumsum(base_haz)
    
    def basehazall(t):
        if sum(unique_ftime<=t)==0:
            return 0
        else: 
            return base_haz[np.max(np.where(unique_ftime <= t))]
    
    base_haz_all = np.array([basehazall(t) for t in time])
    
    #from timeit import default_timer as timer
    #start = timer()
    
    
    #end = timer()
    #print(end - start)  
    return {'cumhazard':base_haz_all, 'survival':np.exp(-base_haz_all), 'time':time}
    


        
    
