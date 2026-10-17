import test from 'node:test';import assert from 'node:assert/strict';
import {validateReply} from '../model.js';
test('Only a bounded plain English-compatible string is accepted',()=>{
 assert.equal(validateReply('{"reply":"Keep your guard up, traveler."}'),'Keep your guard up, traveler.');
 for(const data of ['not json','{}','{"reply":42}','{"reply":""}','{"reply":"\u2603"}',JSON.stringify({reply:'a'.repeat(601)}),JSON.stringify({reply:'word '.repeat(91)})])assert.throws(()=>validateReply(data));
});
