**Permission Grant:**

GRANT USAGE ON SCHEMA public TO cloudpixel\_website\_db\_user;

GRANT CREATE ON SCHEMA public TO cloudpixel\_website\_db\_user;





**Solve database sequence is out of sync issue:**

SELECT setval(

&nbsp;   pg\_get\_serial\_sequence('main\_db\_subject', 'id'),

&nbsp;   COALESCE((SELECT MAX(id) FROM main\_db\_subject), 0) + 1,

&nbsp;   false

);

